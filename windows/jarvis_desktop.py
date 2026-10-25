"""Jarvis Windows desktop client. Requires a reachable Jarvis API backend."""
import json
import os
import threading
import tkinter as tk
from tkinter import simpledialog
from urllib.error import HTTPError, URLError, URLError as URLFailure
from urllib.request import Request, urlopen

DEFAULT_URL = os.environ.get("JARVIS_BASE_URL", "http://127.0.0.1:8000")


class JarvisDesktop:
    def __init__(self, root):
        self.root = root
        self.root.title("Jarvis Personal Assistant")
        self.root.geometry("900x680")
        self.root.minsize(560, 440)
        self.root.configure(bg="#080d18")
        self.base_url = DEFAULT_URL.rstrip("/")
        self.busy = False
        top = tk.Frame(root, bg="#101827", padx=18, pady=14)
        top.pack(fill="x")
        tk.Label(top, text="◉  JARVIS", fg="#75e5ff", bg="#101827", font=("Segoe UI", 18, "bold")).pack(side="left")
        tk.Button(top, text="Backend settings", command=self.settings).pack(side="right")
        self.status = tk.Label(root, text="Checking backend…", bg="#080d18", fg="#a3b5ca", anchor="w", padx=18, pady=8)
        self.status.pack(fill="x")
        self.chat = tk.Text(root, bg="#0c1422", fg="#eef5ff", insertbackground="white", wrap="word", state="disabled", padx=16, pady=16, font=("Segoe UI", 11), relief="flat")
        self.chat.pack(fill="both", expand=True, padx=14, pady=8)
        bottom = tk.Frame(root, bg="#080d18", padx=14, pady=12)
        bottom.pack(fill="x")
        self.input = tk.Text(bottom, height=3, bg="#101827", fg="#eef5ff", insertbackground="white", wrap="word", font=("Segoe UI", 11), relief="flat")
        self.input.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.input.bind("<Control-Return>", self.send_event)
        self.send_button = tk.Button(bottom, text="Send  ↗", command=self.send, bg="#75e5ff", fg="#07121b", padx=18, pady=10, relief="flat")
        self.send_button.pack(side="right")
        self.append("Jarvis", "Hello. Set a reachable backend URL, then send a message.")
        self.check_health()

    def append(self, who, text):
        self.chat.configure(state="normal")
        self.chat.insert("end", f"{who}\n{text}\n\n")
        self.chat.see("end")
        self.chat.configure(state="disabled")

    def request_json(self, path, payload=None, timeout=60):
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"} if data else {}
        req = Request(self.base_url + path, data=data, headers=headers)
        with urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))

    def check_health(self):
        def worker():
            try:
                self.request_json("/health", timeout=5)
                text = "Backend online · " + self.base_url
            except (URLFailure, TimeoutError, ValueError, KeyError):
                text = "Backend unreachable · Configure a reachable URL"
            self.root.after(0, lambda: self.status.configure(text=text))
        threading.Thread(target=worker, daemon=True).start()

    def settings(self):
        value = simpledialog.askstring("Backend settings", "Jarvis API base URL:", initialvalue=self.base_url, parent=self.root)
        if value and value.strip():
            self.base_url = value.strip().rstrip("/")
            self.check_health()

    def send_event(self, _event):
        self.send()
        return "break"

    def send(self):
        message = self.input.get("1.0", "end").strip()
        if not message or self.busy:
            return
        self.input.delete("1.0", "end")
        self.append("You", message)
        self.busy = True
        self.send_button.configure(state="disabled", text="Thinking…")
        def worker():
            try:
                reply = self.request_json("/api/chat", {"message": message})["reply"]
                self.root.after(0, lambda: self.append("Jarvis", str(reply)))
            except HTTPError as exc:
                try:
                    detail = json.loads(exc.read().decode("utf-8")).get("detail", str(exc))
                except (ValueError, TypeError, AttributeError):
                    detail = str(exc)
                self.root.after(0, lambda: self.append("Error", str(detail)))
            except (URLError, TimeoutError, ValueError, KeyError) as exc:
                error_text = str(exc)
                self.root.after(0, lambda error_text=error_text: self.append("Connection error", error_text))
            finally:
                self.root.after(0, self.done)
        threading.Thread(target=worker, daemon=True).start()

    def done(self):
        self.busy = False
        self.send_button.configure(state="normal", text="Send  ↗")


if __name__ == "__main__":
    root = tk.Tk()
    JarvisDesktop(root)
    root.mainloop()
