from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def test_exit_guard_is_installed_after_shell_loads_its_functions():
    source = (ROOT / 'YapLoq.ps1').read_text(encoding='utf-8-sig')
    assert source.rindex('Install-MainWindowCloseGuard $window') > source.rindex('Install-YapLoqShell')


def test_readme_and_moved_notices_have_valid_local_links():
    for relative in ('README.md', '.github/CONTRIBUTING.md', 'docs/LEGAL.md',
                     'docs/PROVIDERS.md', 'docs/THIRD_PARTY_NOTICES.md'):
        path = ROOT / relative
        for target in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
            if '://' in target or target.startswith(('#', 'mailto:')):
                continue
            assert (path.parent / target.split('#')[0]).exists(), (relative, target)


def test_build_metadata_and_packaged_documentation_paths_exist():
    for name in ('version_info.txt', 'version_info_preview.txt', 'requirements-preview.txt'):
        assert (ROOT / 'tools' / name).is_file()
        assert not (ROOT / name).exists()
    for name in ('YapLoq.spec', 'YapLoq-preview.spec'):
        assert "version='tools/version_info" in (ROOT / name).read_text()
    workflow = (ROOT / '.github/workflows/windows-build.yml').read_text()
    assert 'docs/QUICK START.txt' in workflow
    assert 'Copy-Item -LiteralPath docs -Destination dist/YapLoq/docs' in workflow
    assert (ROOT / 'docs/THIRD_PARTY_NOTICES.md').is_file()
