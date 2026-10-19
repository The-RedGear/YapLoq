# Dedicated isolated preview executable.
from PyInstaller.utils.hooks import collect_data_files
aws_data = collect_data_files('botocore', includes=['data/*.json', 'data/polly/**', 'data/sts/**', 'data/sso/**', 'data/sso-oidc/**', 'cacert.pem']) + collect_data_files('boto3')
a = Analysis(
    ['yaploq_preview.py'], pathex=['src'], binaries=[],
    datas=[('YapLoq.ps1', '.'), ('YapLoq.xaml', '.'), ('ImportPreview.xaml', '.'), ('assets', 'assets')] + aws_data,
    hiddenimports=['boto3', 'botocore', 'miniaudio', '_cffi_backend', 'cffi', 'websockets', 'google.auth', 'google.oauth2.service_account'],
    hookspath=[], hooksconfig={}, runtime_hooks=[], excludes=['tkinter', '_tkinter'],
    noarchive=False, optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='YapLoq-preview',
          debug=False, strip=False, upx=False, console=False,
          icon=['assets/YapLoq.ico'], version='version_info_preview.txt')
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='YapLoq-preview')
