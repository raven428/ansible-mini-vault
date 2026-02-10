from __future__ import annotations

ANSIBLE_METADATA = {
  'metadata_version': '1.0.0',
  'status': ['preview'],
  'supported_by': 'community',
}

DOCUMENTATION = r'''
---
module: vault_opera
short_description: Initialize and unseal HashiCorp Vault automatically
description:
  - Checks Vault initialization and seal status via API.
  - Initializes Vault if needed, stores keys and root token to tmpfs.
  - Performs unseal operation automatically using existing or provided keys.
options:
  api_url:
    description:
      - Vault API endpoint URL.
    type: str
    default: 'http://127.0.0.1:8200'  # DevSkim: ignore DS162092
  shares:
    description:
      - Number of unseal key shares to generate during initialization.
    type: int
    default: 5
  threshold:
    description:
      - Number of unseal key shares required to unseal the Vault.
    type: int
    default: 3
  keys_dir:
    description:
      - Directory where unseal keys and root token are stored.
      - Must reside on a tmpfs, have 0700 permissions and be owned by root.
    type: str
    default: '/deploy/secure/vault'
  keys_list:
    description:
      - Optional list of unseal keys to use if no key files are found in C(keys_dir).
      - Useful for automated unseal without writing keys to disk.
      - Keys must be provided in base64-encoded format.
    type: list
    elements: str
    default: []
author:
  - ChatGPT (https://chatgpt.com)
  - Dmitry Sukhodoyev (https://github.com/raven428/ansible-mini-vault)
'''

EXAMPLES = r'''
- name: Initialize and unseal Vault
  vault_opera:
    api_url: http://127.0.0.1:8200  # DevSkim: ignore DS162092
    shares: 5
    threshold: 3
    keys_dir: /deploy/secure/vault
'''

RETURN = r'''
changed:
  description: Whether Vault was initialized or unsealed.
  type: bool
seal_status:
  description: Last /v1/sys/seal-status response.
  type: dict
'''

import contextlib
import ctypes
import ctypes.util
import json
import os
import stat
from pathlib import Path

# pylint: disable=import-error
import requests  # type: ignore[reportMissingImports]

# pylint: disable=import-error
from ansible.module_utils.basic import (  # type: ignore[reportMissingImports]
  AnsibleModule,
)

# Load libc dynamically
libc_path = ctypes.util.find_library('c')
if not libc_path:
  msg = 'libc not found'
  raise RuntimeError(msg)
libc = ctypes.CDLL(libc_path, use_errno=True)

# Try to resolve flags dynamically (fallback to hardcoded)
MS_NODEV = getattr(libc, 'MS_NODEV', 4)
MS_NOEXEC = getattr(libc, 'MS_NOEXEC', 8)
MS_NOSUID = getattr(libc, 'MS_NOSUID', 2)


def mount_tmpfs(path: Path, size: str | None = None, mode: int | None = None) -> None:
  '''
  Mount a tmpfs to the specified directory without external binaries.
  Raises:
    OSError: If the mount operation fails.
  '''
  path.mkdir(parents=True, exist_ok=True)
  tmpfs = b'tmpfs'
  data_parts = []
  if size is not None:
    data_parts.append(f'size={size}')
  if mode is not None:
    data_parts.append(f'mode={mode:o}')
  data = ','.join(data_parts).encode() if data_parts else None
  ret = libc.mount(
    tmpfs,
    str(path).encode(),
    tmpfs,
    MS_NODEV | MS_NOEXEC | MS_NOSUID,
    data,
  )
  if ret != 0:
    errno = ctypes.get_errno()
    raise OSError(errno, f'Failed to mount tmpfs on {path}: {os.strerror(errno)}')


def umount_tmpfs(path: Path) -> None:
  '''
  Unmount tmpfs.
  Raises:
    OSError: If the unmount operation fails.
  '''
  ret = libc.umount(str(path).encode())
  if ret != 0:
    errno = ctypes.get_errno()
    raise OSError(errno, f'Failed to unmount {path}: {os.strerror(errno)}')


class Vault:
  '''Encapsulates Vault API operations and key management.'''
  def __init__(self, module: AnsibleModule) -> None:
    self.module = module
    self.api_url = module.params['api_url'].rstrip('/')
    self.shares = module.params['shares']
    self.threshold = module.params['threshold']
    self.keys_dir = Path(module.params['keys_dir'])
    self.keys_list = module.params['keys_list']

  def vault_put(self, endpoint: str, data: dict, timeout: int = 5) -> dict:
    try:
      response = requests.put(endpoint, json=data, timeout=timeout)
      response.raise_for_status()
      return response.json()
    except (requests.RequestException, json.JSONDecodeError) as err:
      self.module.fail_json(msg=f'Vault PUT failed: {err}')
    return {}  # for mypy

  def get_seal_status(self) -> dict:
    try:
      response = requests.get(f'{self.api_url}/v1/sys/seal-status', timeout=5)
      response.raise_for_status()
      return response.json()
    except (requests.RequestException, json.JSONDecodeError) as err:
      if self.module.check_mode:
        pass
      else:
        self.module.fail_json(msg=f'Get seal status failed: {err}')
    return {}  # for mypy

  def _store_keys(self, init_resp: dict) -> None:
    try:
      (self.keys_dir / 'root_token').write_text(
        init_resp['root_token'] + '\n',
        encoding='utf-8',
      )
      for i, key in enumerate(init_resp.get('keys_base64', []), start=1):
        (self.keys_dir / f'unseal{i:02d}').write_text(
          key + '\n',
          encoding='utf-8',
        )
    except OSError as err:
      self.module.fail_json(msg=f'Failed to store keys: {err}')

  def keys_secure_dir(self) -> bool:
    '''
    Ensure the directory exists, is on tmpfs, owned by root, and mode 0700.
    Returns:
      bool: True if the directory exists on tmpfs and meets security requirements,
        False otherwise.
    Raises:
      PermissionError: in case of wrong permissions
      FileNotFoundError: If directory cannot be checked
    '''
    p = self.keys_dir.resolve()
    if not p.exists():
      p.mkdir(parents=True, exist_ok=True, mode=0o700)
    st = p.stat()
    if st.st_uid != 0:
      msg = f'Path [{p}] must be owned by uid=0, got [{st.st_uid}] uid'
      raise PermissionError(msg)
    if stat.S_IMODE(st.st_mode) != 0o700:  # noqa: PLR2004
      msg = f'Path [{p}] must 0700, got [{oct(stat.S_IMODE(st.st_mode))}] mode'
      raise PermissionError(msg)
    try:
      mounts = Path('/proc/mounts').read_text(encoding='utf-8').splitlines()
    except FileNotFoundError as err:
      msg = f'Type of [{p}] unknown, file [/proc/mounts] not found'
      raise FileNotFoundError(msg) from err
    best_match = ('', '')
    for line in mounts:
      parts = line.split()
      if len(parts) >= 3 and str(p).startswith(  # noqa: PLR2004
        parts[1],
      ) and len(parts[1]) > len(best_match[0]):
        best_match = (parts[1], parts[2])
    return best_match[1] == 'tmpfs'

  def init(self) -> tuple[dict, bool]:
    status = self.get_seal_status()
    if status.get('initialized', False):
      return status, False
    keys_secure_dir = False
    try:
      keys_secure_dir = self.keys_secure_dir()
    except FileNotFoundError as err:
      self.module.fail_json(msg=str(err))
    except PermissionError:
      try:
        if not self.module.check_mode:
          umount_tmpfs(self.keys_dir)
      except OSError as err:
        self.module.fail_json(msg=str(err))
    if not self.module.check_mode:
      if not keys_secure_dir:
        mount_tmpfs(path=self.keys_dir, mode=0o700)
      init_resp = self.vault_put(
        f'{self.api_url}/v1/sys/init',
        {
          'secret_shares': self.shares,
          'secret_threshold': self.threshold,
        },
        22,
      )
      self._store_keys(init_resp)
    return self.get_seal_status(), True

  def unseal(self) -> tuple[dict, bool]:
    keys: list[str] = []
    with contextlib.suppress(OSError):
      keys = self.keys_list or [
        p.read_text(encoding='utf-8').strip()
        for p in sorted(self.keys_dir.glob('unseal*')) if p.is_file()
      ]
    if not keys:
      self.module.fail_json(
        msg=f'Empty keys_list and no key files found in [{self.keys_dir}] dir',
      )
    for key in keys:
      if not self.module.check_mode:
        self.vault_put(
          f'{self.api_url}/v1/sys/unseal',
          {
            'key': key,
          },
        )
        status = self.get_seal_status()
        if not status.get('sealed', True):
          return (
            {
              **self.get_seal_status(),
              'keys_source':
                'variable' if self.keys_list else 'files',
            },
            True,
          )
    if not self.module.check_mode:
      self.module.fail_json(msg='All keys used, but Vault is still sealed')
    return self.get_seal_status(), False


def main() -> None:
  module = AnsibleModule(
    argument_spec={
      'api_url': {
        'type': 'str',
        'default': 'http://127.0.0.1:8200',  # DevSkim: ignore DS162092
      },
      'shares': {
        'type': 'int',
        'default': 5,
      },
      'threshold': {
        'type': 'int',
        'default': 3,
      },
      'keys_dir': {
        'type': 'str',
        'default': '/deploy/secure/vault',
      },
      'keys_list': {
        'type': 'list',
        'elements': 'str',
        'default': [],
      },
    },
    supports_check_mode=True,
  )

  vault = Vault(module)
  status, changed = vault.init()
  if status.get('sealed', False):
    status, unsealed = vault.unseal()
    changed = changed or unsealed

  module.exit_json(changed=changed, seal_status=status)


if __name__ == '__main__':
  main()
