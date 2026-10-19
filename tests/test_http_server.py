import json
import tempfile
import time
import unittest
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from unittest.mock import patch
from unittest.mock import Mock

from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.server import BridgeServers
from voice_studio_speaker_bridge.settings import Settings


class HttpServerTests(unittest.TestCase):
    def test_action_validation_has_no_save_or_backup_side_effects(self):
        payload = {'rules': []}
        before = self.settings.path.read_bytes() if self.settings.path.exists() else None
        request = Request(f'http://127.0.0.1:{self.port}/api/maintenance/validate-actions', data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
        with urlopen(request) as response:
            self.assertEqual(json.loads(response.read())['result']['rules'], [])
        self.assertEqual(self.settings.path.read_bytes() if self.settings.path.exists() else None, before)
        self.assertFalse((self.settings.path.parent / 'backups').exists())

    def test_change_queued_voice_route(self):
        payload = dict(speechId='waiting-id', voice='EventVoice')
        request = Request(f'http://127.0.0.1:{self.port}/api/queue/voice', data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
        with urlopen(request) as response:
            self.assertTrue(json.loads(response.read())['ok'])
        self.protocol.execute.assert_called_once_with('ChangeSpeechVoice', payload)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(Path(self.temp.name) / "settings.json")
        self.settings.http_port = 0
        self.settings.enable_udp = False
        self.protocol = Mock()
        self.protocol.execute.return_value = {"speechId": "123"}
        self.server = BridgeServers(self.settings, self.protocol, EventBus())
        self.server.http_thread = __import__("threading").Thread(
            target=self.server._run_http, daemon=True
        )
        self.server.http_thread.start()
        for _ in range(100):
            if self.server.http_server is not None:
                break
            time.sleep(0.01)
        self.port = self.server.http_server.server_address[1]

    def tearDown(self):
        self.server.stop()
        self.temp.cleanup()

    def test_health_lists_aliases(self):
        with urlopen(f"http://127.0.0.1:{self.port}/health") as response:
            result = json.loads(response.read())
        self.assertTrue(result["ok"])
        self.assertIn("EventVoice", result["aliases"])

    def test_viewer_assignment_http_roundtrip_uses_data_folder(self):
        from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
        self.server.protocol = SpeakerBotProtocol(self.settings, Mock())
        payload = dict(platform='twitch', userId='123', displayName='Viewer', voice='EventVoice')
        request = Request(f'http://127.0.0.1:{self.port}/api/viewers/set', data=json.dumps(payload).encode(), method='POST')
        with urlopen(request) as response:
            self.assertEqual(json.loads(response.read())['result']['voice'], 'EventVoice')
        with urlopen(f'http://127.0.0.1:{self.port}/api/viewers') as response:
            self.assertEqual(json.loads(response.read())['result']['viewers'][0]['userId'], '123')
        self.assertTrue((self.settings.path.parent / 'viewers.json').is_file())

    def test_automations_project_legacy_without_mutating_then_save_with_backup(self):
        self.settings.streamerbot_queued_action = 'Existing avatar'
        self.settings.streamerbot_actions_enabled = True
        self.settings.save()
        with urlopen(f'http://127.0.0.1:{self.port}/api/automations') as response:
            draft = json.loads(response.read())['result']
        self.assertFalse(self.settings.automations_migrated)
        self.assertEqual(draft['rules'][0]['steps'][0]['action'], 'Existing avatar')
        request = Request(f'http://127.0.0.1:{self.port}/api/automations/save',
                          data=json.dumps({'rules': draft['rules']}).encode(), method='POST')
        with urlopen(request) as response:
            self.assertTrue(json.loads(response.read())['ok'])
        saved = Settings(self.settings.path)
        self.assertTrue(saved.automations_migrated)
        self.assertEqual(saved.automations[0]['steps'][0]['action'], 'Existing avatar')
        self.assertTrue(list((self.settings.path.parent / 'backups').glob('*.zip')))
        self.protocol.execute.assert_not_called()

    def test_invalid_automation_does_not_overwrite_saved_settings(self):
        self.settings.save()
        before = self.settings.path.read_bytes()
        request = Request(f'http://127.0.0.1:{self.port}/api/automations/save', data=b'{"rules":[{"name":"Incomplete"}]}', method='POST')
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code, 400)
        self.assertEqual(self.settings.path.read_bytes(), before)

    def test_integration_status_is_real_listener_state(self):
        with urlopen(f'http://127.0.0.1:{self.port}/api/integrations/status') as response:
            result = json.loads(response.read())['result']
        self.assertEqual(result['state'], 'disabled')
        self.assertEqual(result['received'], 0)
        self.protocol.execute.assert_not_called()

    def test_listener_test_rejects_when_listener_is_not_running(self):
        request = Request(f'http://127.0.0.1:{self.port}/api/integrations/udp-test', data=b'{}', method='POST')
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code, 400)
        self.protocol.execute.assert_not_called()

    def test_playback_snapshot_includes_listener_diagnostics(self):
        with urlopen(f'http://127.0.0.1:{self.port}/api/state') as response:
            result = json.loads(response.read())['result']
        self.assertEqual(result['integration']['state'], 'disabled')
        self.assertEqual(result['speechId'], '123')

    def test_speak_passes_voice_and_message(self):
        body = json.dumps({"voice": "EventVoice", "message": "hello"}).encode()
        request = Request(
            f"http://127.0.0.1:{self.port}/speak",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request) as response:
            result = json.loads(response.read())
        self.assertTrue(result["ok"])
        self.protocol.execute.assert_called_once_with(
            "Speak", {"voice": "EventVoice", "message": "hello"}
        )

    def test_update_mutations_require_desktop_token(self):
        request=Request(f'http://127.0.0.1:{self.port}/api/updates/download',data=b'{}',method='POST')
        with patch.dict('os.environ',{'YAPLOQ_UPDATE_TOKEN':'private-desktop-token'}):
            with self.assertRaises(HTTPError) as error:urlopen(request)
        self.assertEqual(error.exception.code,403)

    def test_update_check_is_async_and_does_not_execute_speech(self):
        request=Request(f'http://127.0.0.1:{self.port}/api/updates/check',data=b'{}',method='POST',headers={'X-YapLoq-Update-Token':'private-desktop-token'})
        with patch.dict('os.environ',{'YAPLOQ_UPDATE_TOKEN':'private-desktop-token'}), patch.object(self.server.updates,'check',return_value={'state':'checking'}):
            with urlopen(request) as response:result=json.loads(response.read())
        self.assertEqual(result['result']['state'],'checking')
        self.protocol.execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
