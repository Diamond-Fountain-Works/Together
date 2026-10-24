"""Parse actual Swift Testing outcomes without promoting skips to passes."""
import re


def swift_test_evidence(text, name, *, endpoint_ready=True):
    """Require one completed execution of an exact, non-parameterized test."""
    escaped = re.escape(name)
    passed = len(re.findall(r"^✔ Test " + escaped + r" passed(?: after |\.|$)", text, re.M))
    failed = len(re.findall(r"^✘ Test " + escaped + r" failed(?: after |\.|$)", text, re.M))
    skipped = len(re.findall(r"^➜ Test " + escaped + r" skipped(?:[ .]|$)", text, re.M))
    status = "PASS" if endpoint_ready and passed == 1 and failed == skipped == 0 else "FAIL" if failed or passed > 1 else "NOT RUN"
    return {"status": status, "passedCount": passed, "failedCount": failed,
            "skippedCount": skipped, "requiredExecutedCount": 1}
