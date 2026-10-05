import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "app"))
from main import Processor, create_app, result_name  # noqa: E402


class FakeProcessor:
    def __init__(self):
        self.events = []

    def process(self, event):
        self.events.append(event)
        if event["name"] == "reports/retry.json":
            raise RuntimeError("temporary AI outage")
        if event["name"] == "reports/invalid.json":
            raise ValueError("bad input")
        return {"status": "created", "result": result_name(event["name"], event["generation"])}


def test_http_contract_and_retry():
    fake = FakeProcessor()
    client = create_app(fake).test_client()
    headers = {"ce-type": "google.cloud.storage.object.v1.finalized", "ce-id": "demo-1"}
    event = {"bucket": "input", "name": "reports/01.json", "generation": "42"}
    assert client.post("/", json=event, headers=headers).json["status"] == "created"
    assert client.post("/", json={**event, "name": "reports/retry.json"}, headers=headers).status_code == 503
    assert client.post("/", json={**event, "name": "reports/invalid.json"}, headers=headers).status_code == 200
    assert client.post("/", json=event).status_code == 400
    assert client.get("/healthz").json == {"status": "ok"}


def test_generation_specific_idempotency_key():
    assert result_name("reports/a.json", 1) == result_name("reports/a.json", 1)
    assert result_name("reports/a.json", 1) != result_name("reports/a.json", 2)


def test_processor_writes_once_for_same_generation():
    class Blob:
        def __init__(self, name, generation=None):
            self.name, self.generation = name, generation
            self.saved = None

        def exists(self):
            return self.saved is not None

        def download_as_bytes(self):
            assert self.generation == 42
            return b'{"incident_id":"A1","location":"Bridge","report":"A tram stopped"}'

        def upload_from_string(self, payload, **kwargs):
            assert kwargs["if_generation_match"] == 0
            self.saved = payload

    class Bucket:
        def __init__(self):
            self.blobs = {}

        def blob(self, name, generation=None):
            key = (name, generation)
            return self.blobs.setdefault(key, Blob(name, generation))

    class Storage:
        def __init__(self):
            self.buckets = {}

        def bucket(self, name):
            return self.buckets.setdefault(name, Bucket())

    class Models:
        calls = 0

        def generate_content(self, **kwargs):
            self.calls += 1
            return type("Response", (), {"text": '{"category":"transit","severity":"high",'
                                                  '"summary":"Stopped tram","entities":["Bridge"],'
                                                  '"suggested_action":"Review report","uncertainty":"Unverified"}'})()

    worker = Processor.__new__(Processor)
    worker.input_bucket, worker.output_bucket, worker.model = "input", "output", "gemini-2.5-flash"
    worker.storage = Storage()
    models = Models()
    worker.ai = type("AI", (), {"models": models})()
    event = {"bucket": "input", "name": "reports/tram.json", "generation": "42"}
    assert worker.process(event)["status"] == "created"
    assert worker.process(event)["status"] == "duplicate"
    assert models.calls == 1
    saved = worker.storage.bucket("output").blob(result_name(event["name"], 42)).saved
    assert __import__("json").loads(saved)["review_required"] is True
