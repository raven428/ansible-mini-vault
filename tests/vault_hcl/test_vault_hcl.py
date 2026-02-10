from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from ansible.errors import AnsibleUndefinedVariable
from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar

CASES_DIR = Path(__file__).parent / 'cases'
TEMPLATE_PATH = Path(__file__).parent.parent.parent / 'templates' / 'vault-hcl.j2'


def prepare_config(yaml_content: str) -> dict:
  raw_config = yaml.safe_load(yaml_content)
  loader = DataLoader()
  templar = Templar(loader)
  # First pass: render dict/list variables (except 'v') with simple context
  simple_context = {
    k: v
    for k, v in raw_config.items() if k != 'v' and not isinstance(v, (dict, list))
  }
  templar.available_variables = simple_context
  for key in list(raw_config.keys()):
    if key != 'v' and isinstance(raw_config[key], (dict, list)):
      raw_config[key] = templar.template(raw_config[key])
  # Second pass: render all values with full context
  templar.available_variables = {
    k: v
    for k, v in raw_config.items() if k != 'v'
  }
  return templar.template(raw_config)


def render_template_with_templar(template_path: Path, config: dict) -> str:
  loader = DataLoader()
  templar = Templar(loader)
  templar.available_variables = config
  template_content = template_path.read_text(encoding='utf-8')
  return templar.template(template_content, escape_backslashes=False)


def collect_test_cases() -> list[str]:
  yaml_files = sorted(CASES_DIR.glob('*.yaml'))
  return [f.stem for f in yaml_files]


@pytest.mark.parametrize('case_name', collect_test_cases())
def test_vault_template_generation(case_name: str) -> None:
  yaml_path = CASES_DIR / f'{case_name}.yaml'
  hcl_path = CASES_DIR / f'{case_name}.hcl'
  yaml_content = yaml_path.read_text(encoding='utf-8')
  if 'undefined' in case_name:
    with pytest.raises(AnsibleUndefinedVariable):  # noqa: PT012
      config = prepare_config(yaml_content)
      render_template_with_templar(TEMPLATE_PATH, config)
  elif not hcl_path.exists():
    pytest.fail(f'Expected HCL file not found: {hcl_path}')
  else:
    config = prepare_config(yaml_content)
    expected = hcl_path.read_text(encoding='utf-8')
    rendered = render_template_with_templar(TEMPLATE_PATH, config)
    assert rendered == expected, (  # noqa: S101
      f'Output mismatch for {case_name}:\nGot:\n{rendered}\n\nExpected:\n{expected}'
    )
