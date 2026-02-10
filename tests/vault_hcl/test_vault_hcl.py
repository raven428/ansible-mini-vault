from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from ansible.errors import AnsibleUndefinedVariable
from ansible.parsing.dataloader import DataLoader
from ansible.plugins.filter.core import combine as ansible_combine
from ansible.template import Templar
from jinja2 import (
  Environment,
  FileSystemLoader,
  StrictUndefined,
  Template,
  UndefinedError,
  select_autoescape,
)


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


@pytest.fixture
def template_env() -> Environment:
  template_dir = Path(__file__).parent.parent.parent / 'templates'
  env = Environment(
    loader=FileSystemLoader(template_dir),
    undefined=StrictUndefined,
    keep_trailing_newline=True,
    autoescape=select_autoescape(enabled_extensions=('html', 'xml')),
  )

  env.filters['combine'] = ansible_combine
  return env


@pytest.fixture
def vault_template(template_env: Environment) -> Template:
  return template_env.get_template('vault-hcl.j2')


def collect_test_cases() -> list[str]:
  cases_dir = Path(__file__).parent / 'cases'
  yaml_files = sorted(cases_dir.glob('*.yaml'))
  return [f.stem for f in yaml_files]


@pytest.mark.parametrize('case_name', collect_test_cases())
def test_vault_template_generation(vault_template: Template, case_name: str) -> None:
  cases_dir = Path(__file__).parent / 'cases'
  yaml_path = cases_dir / f'{case_name}.yaml'
  hcl_path = cases_dir / f'{case_name}.hcl'

  yaml_content = yaml_path.read_text()

  if 'undefined' in case_name:
    with pytest.raises((AnsibleUndefinedVariable, UndefinedError)):  # noqa: PT012
      config = prepare_config(yaml_content)
      vault_template.render(**config)
  elif not hcl_path.exists():
    pytest.fail(f'Expected HCL file not found: {hcl_path}')
  else:
    config = prepare_config(yaml_content)
    expected = hcl_path.read_text()
    rendered = vault_template.render(**config)
    assert rendered == expected, (  # noqa: S101
      f'Output mismatch for {case_name}:\nGot:\n{rendered}\n\nExpected:\n{expected}'
    )
