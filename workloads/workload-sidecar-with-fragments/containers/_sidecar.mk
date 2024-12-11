ALL: .image_build .image_push sidecar_config.json sidecar_fragment.rego.cose oras_discover fragment_import_rules.json

.PHONY: clean oras_clean oras_attach show feed_issuer oras_discover

clean:
	rm -f *.json *.rego *.rego.cose .image_build .image_push

.image_build: Dockerfile sidecar_server.py
	make clean
	docker buildx build -t $(SIDECAR_IMAGE) .
	touch .image_build

.image_push: .image_build
	docker push $(SIDECAR_IMAGE)
	make oras_clean
	touch .image_push

sidecar_config.json: ../../sidecar_config.json.template
	sed "s|<IMAGE>|${SIDECAR_IMAGE}|g" ../../sidecar_config.json.template > sidecar_config.json
	cat sidecar_config.json

CHAIN = ../../certs/intermediateCA/certs/www.contoso.com.chain.cert.pem
KEY = ../../certs/intermediateCA/private/ec_p384_private.pem

sidecar_fragment.rego sidecar_fragment.rego.cose: sidecar_config.json ${CHAIN} ${KEY} .image_push
	$(eval MAYBE_DEBUG=$(shell if [ "${POLICY_TYPE}" = "debug" ]; then echo "--debug-mode"; fi))
	$(eval MAYBE_OMIT_ID=$(shell if [ "${OMIT_ID}" = "true" ]; then echo "--omit-id"; fi))
	az confcom acifragmentgen \
		--chain ${CHAIN} \
		--key ${KEY} \
		--svn 1 \
		--namespace contoso \
		--input ./sidecar_config.json \
		--feed ${FEED} \
		--upload-fragment \
		--no-print \
		${MAYBE_DEBUG} \
		${MAYBE_OMIT_ID} \
		--output-filename sidecar_fragment # produces sidecar_fragment.rego and sidecar_fragment.rego.cose

sidecar_fragment_sign1util: sidecar_fragment.rego oras_clean
	$(eval ISSUER_DID=$(shell sign1util did-x509 -chain ${CHAIN} -policy CN))
	sign1util create -algo ES384 -chain ${CHAIN} -claims $< -key ${KEY} -out sidecar_fragment.rego.cose -salt zero \
		-feed ${FEED} -content-type application/unknown+rego \
		-issuer ${ISSUER_DID}

oras_attach:
	oras attach ${SIDECAR_IMAGE} \
		--artifact-type application/x-ms-ccepolicy-frag \
		./sidecar_fragment.rego.cose:application/cose-x509+rego

show:
	cat sidecar_fragment.rego
	make oras_discover
	cat fragment_import_rules.json
	@echo

feed_issuer:
	sign1util print -in sidecar_fragment.rego.cose | grep -E 'feed:|iss:'
	grep -E 'feed|issuer' policy_workload_sidecar_with_fragments.rego

oras_discover:
	oras discover ${SIDECAR_IMAGE} --artifact-type application/x-ms-ccepolicy-frag

oras_clean:
	oras discover ${SIDECAR_IMAGE} --artifact-type application/x-ms-ccepolicy-frag --format json | jq -r '.manifests[].reference' | xargs --no-run-if-empty -n 1 oras manifest delete -f

fragment_import_rules.json: sidecar_fragment.rego.cose
	az confcom acifragmentgen --generate-import -p ./sidecar_fragment.rego.cose --minimum-svn 1 --fragments-json fragment_import_rules.json
