.PHONY: qa copy-qa build test package install server-test ui-test visual-qa visual-review protocol-test security-qa
qa:
	./scripts/qa.sh
copy-qa:
	python3 scripts/audit_ui_copy.py --json qa/results/copy.json
build:
	python3 scripts/run_project.py build
test:
	python3 scripts/run_project.py test
package:
	python3 scripts/run_project.py package
install:
	python3 scripts/install_local.py
server-test:
	cd services/relay && npm test
ui-test:
	python3 scripts/run_ui_tests.py
visual-qa:
	.qa-runtime/bin/python scripts/compare_visuals.py
visual-review:
	.qa-runtime/bin/python scripts/build_visual_review.py
protocol-test:
	.qa-runtime/bin/python -m unittest discover -s tests/conformance -v
	swift test --package-path packages/together-core-swift --filter ProtocolConformanceTests
security-qa:
	python3 scripts/test_repository_safety.py
	python3 scripts/audit_repository_safety.py --json qa/results/repository-safety.json
