ALL: .primary_policy

.PHONY: clean primary_policy deploy show

DEPLOY_SCRIPT ?= c-aci-testing aci deploy

clean:
	rm -f .param_set .primary_policy *.rego *.cose

.param_set:
	if [ "${REPO}" != "" ]; then \
		c-aci-testing aci param_set . --parameter "repository_primary=${REPO}"; \
	fi
	c-aci-testing aci param_set . --parameter "repository_sidecar=${SIDECAR_REPO}"
	touch .param_set

.primary_policy: ../../fragment_import_rules.json .param_set *.bicep
	c-aci-testing policies gen . --deployment-name ${DEPLOYMENT_NAME} --fragments-json ../../fragment_import_rules.json
	../check-policy.sh policy_*.rego
	touch .primary_policy

primary_policy: .primary_policy

deploy: .primary_policy
	DEPLOYMENT_NAME=${DEPLOYMENT_NAME} ${DEPLOY_SCRIPT} .

show:
	@echo cat policy_*.rego
	@cat policy_*.rego

verify:
	c-aci-testing aci monitor --deployment-name ${DEPLOYMENT_NAME} | tee monitor.out
	grep -q ${VERIFY_KEYWORD} monitor.out
	rm monitor.out
