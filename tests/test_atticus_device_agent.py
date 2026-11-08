from __future__ import annotations

# ruff: noqa: I001 -- keep the test's importlib-based platform loader together

import base64
import importlib.util
import sys
import types
from pathlib import Path
from unittest.mock import Mock

import pytest


AGENT_PATH = Path(__file__).resolve().parents[1] / "windows" / "jarvis_device_agent.py"


def load_agent(monkeypatch):
    fake = types.ModuleType("winctl")
    fake.launch = Mock(return_value=True)
    fake.paste_into = Mock(return_value="text pasted")
    fake.keys = Mock()
    fake.front = Mock(return_value=("Chrome", "Example", 123))
    fake.monitors = Mock(return_value=[{"name": "Primary Display"}])

    def capture(_monitor, destination):
        Path(destination).write_bytes(b"jarvis-test-screen")

    fake.capture = Mock(side_effect=capture)
    monkeypatch.setitem(sys.modules, "winctl", fake)

    spec = importlib.util.spec_from_file_location("jarvis_device_agent_under_test", AGENT_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, fake


def test_atticus_agent_opens_only_allowlisted_apps(monkeypatch):
    agent, winctl = load_agent(monkeypatch)
    result = agent.execute("open_app", {"app": "notepad"})
    assert result == {"opened": True, "app": "notepad"}
    winctl.launch.assert_called_once_with("Notepad")
    with pytest.raises(ValueError, match="not allow-listed"):
        agent.execute("open_app", {"app": "powershell"})


def test_atticus_agent_allows_https_only(monkeypatch):
    agent, _ = load_agent(monkeypatch)
    opened = []
    monkeypatch.setattr(agent.webbrowser, "open", lambda url, new=0: opened.append((url, new)) or True)
    assert agent.execute("open_url", {"url": "https://example.com"}) == {"opened": True}
    assert opened == [("https://example.com", 2)]
    with pytest.raises(ValueError, match="Only HTTPS"):
        agent.execute("open_url", {"url": "http://example.com"})


def test_atticus_agent_types_text_through_upstream_clipboard_helper(monkeypatch):
    agent, winctl = load_agent(monkeypatch)
    assert agent.execute("type_text", {"text": "Hello Jarvis"}) == {"detail": "text pasted"}
    winctl.paste_into.assert_called_once_with("", "Hello Jarvis")
    with pytest.raises(ValueError, match="length"):
        agent.execute("type_text", {"text": ""})


def test_atticus_agent_restricts_keypresses(monkeypatch):
    agent, winctl = load_agent(monkeypatch)
    assert agent.execute("press_key", {"key": "CTRL+S"}) == {"pressed": "CTRL+S"}
    winctl.keys.assert_called_once_with(0x11, 0x53)
    with pytest.raises(ValueError, match="not allow-listed"):
        agent.execute("press_key", {"key": "ALT+F4"})


def test_atticus_agent_reports_status_and_returns_screenshot(monkeypatch):
    agent, winctl = load_agent(monkeypatch)
    status = agent.execute("get_status", {})
    assert status["platform"] == "windows"
    assert status["foreground_app"] == "Chrome"
    shot = agent.execute("screenshot", {})
    assert shot["mime_type"] == "image/jpeg"
    assert shot["display"] == "Primary Display"
    assert base64.b64decode(shot["image_base64"]) == b"jarvis-test-screen"
    winctl.capture.assert_called_once()
