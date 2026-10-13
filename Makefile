.PHONY: qa copy-qa build test package install server-test ui-test visual-qa
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
	cd server && npm test
ui-test:
	python3 scripts/run_ui_tests.py
visual-qa:
	.qa-runtime/bin/python scripts/compare_visuals.py
