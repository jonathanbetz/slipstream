"""Tests for slipstream/lib.py utilities."""

import json
import threading

import slipstream.lib as lib


def test_project_key_for():
    assert lib.project_key_for("/Users/alice/src/app") == "-Users-alice-src-app"
    assert lib.project_key_for("/tmp") == "-tmp"
    assert lib.project_key_for("") == ""


def test_now_iso_format():
    ts = lib.now_iso()
    assert ts.endswith("Z")
    assert "T" in ts
    assert len(ts) == 20  # YYYY-MM-DDTHH:MM:SSZ


def test_write_log_creates_file(tmp_home):
    log = lib.DATA_DIR / "projects" / "test" / "permissions.jsonl"
    lib.write_log(log, {"foo": "bar"})
    assert log.is_file()
    record = json.loads(log.read_text().strip())
    assert record == {"foo": "bar"}


def test_write_log_appends(tmp_home):
    log = lib.DATA_DIR / "test.jsonl"
    lib.write_log(log, {"n": 1})
    lib.write_log(log, {"n": 2})
    lines = [json.loads(l) for l in log.read_text().splitlines()]
    assert lines == [{"n": 1}, {"n": 2}]


def test_write_log_concurrent(tmp_home):
    """10 concurrent threads must each produce exactly one valid JSON line."""
    log = lib.DATA_DIR / "concurrent.jsonl"
    n = 10

    def write_one(i):
        lib.write_log(log, {"i": i})

    threads = [threading.Thread(target=write_one, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    lines = log.read_text().splitlines()
    assert len(lines) == n
    for line in lines:
        json.loads(line)  # must be valid JSON


def test_validate_json_valid(tmp_home):
    result = lib.validate_json('{"key": "value"}', "test")
    assert result == {"key": "value"}


def test_validate_json_malformed(tmp_home):
    result = lib.validate_json("not json {{{", "my-script")
    assert result is None
    err_log = lib.DATA_DIR / "errors.log"
    assert err_log.is_file()
    content = err_log.read_text()
    assert "my-script" in content
    assert "malformed JSON" in content


def test_log_error(tmp_home):
    lib.log_error("something went wrong")
    err_log = lib.DATA_DIR / "errors.log"
    assert err_log.is_file()
    content = err_log.read_text()
    assert "[slipstream]" in content
    assert "something went wrong" in content
