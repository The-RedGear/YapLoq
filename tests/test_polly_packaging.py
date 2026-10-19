from pathlib import Path

from wpf_launcher import _verify_polly_runtime


def test_polly_runtime_data_and_client_construct_without_credentials_or_network(monkeypatch):
    def no_network(*args, **kwargs):
        raise AssertionError('Package validation must not contact AWS')
    import botocore.endpoint
    monkeypatch.setattr(botocore.endpoint.Endpoint, 'make_request', no_network)
    assert _verify_polly_runtime()['ok']


def test_both_distributions_bundle_aws_models_endpoints_and_certificates():
    root = Path(__file__).resolve().parents[1]
    for name in ('YapLoq.spec', 'YapLoq-preview.spec'):
        source = (root / name).read_text()
        assert "collect_data_files('botocore'" in source
        assert all(value in source for value in ('data/*.json', 'data/polly/**', 'data/sts/**', 'cacert.pem', '+ aws_data'))
