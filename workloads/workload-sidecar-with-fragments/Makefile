all: certs login images fragments policies

.PHONY: all clean clean_allbutcerts login images clean_images fragments show oras_attach oras_clean deploy policies verify generate_vm_scripts

CHAIN = certs/intermediateCA/certs/www.contoso.com.chain.cert.pem
KEY = certs/intermediateCA/private/ec_p384_private.pem

${CHAIN} ${KEY}:
	./certs/create_certchain.sh

certs: ${CHAIN} ${KEY}

login:
	az acr login --name ${REGISTRY}

clean: clean_allbutcerts
	rm -rf certs/intermediateCA/ certs/rootCA/

clean_allbutcerts:
	rm -f *.json *.rego *.rego.cose
	make -C containers/primary clean
	make -C containers/sidecar-a clean
	make -C containers/sidecar-b clean
	make -C deployments/primary-sidecar-a clean
	make -C deployments/primary-sidecar-b clean
	make -C deployments/just-sidecar clean
	rm lcows_fragment.tar.gz

images:
	make -C containers/primary .image_push
	make -C containers/sidecar-a .image_push
	make -C containers/sidecar-b .image_push

clean_images: clean_allbutcerts images

fragments: fragment_import_rules.json

fragment_import_rules.json: certs
	make -C containers/sidecar-a
	make -C containers/sidecar-b
	cmp containers/sidecar-a/fragment_import_rules.json containers/sidecar-b/fragment_import_rules.json
	cp containers/sidecar-a/fragment_import_rules.json fragment_import_rules.json

primary_sidecar_policy.rego: fragment_import_rules.json
	make -C deployments/primary-sidecar-a primary_policy
	make -C deployments/primary-sidecar-b primary_policy
	cmp deployments/primary-sidecar-a/policy_*.rego deployments/primary-sidecar-b/policy_*.rego
	cp deployments/primary-sidecar-a/policy_*.rego ./primary_sidecar_policy.rego

policies: primary_sidecar_policy.rego
	make -C deployments/just-sidecar primary_policy

show:
	make fragments
	make -C containers/sidecar-a show
	make -C containers/sidecar-b show
	make policies
	cat primary_sidecar_policy.rego
	cat deployments/just-sidecar/policy_*.rego

deploy: all
	make -C deployments/primary-sidecar-a deploy
	make -C deployments/primary-sidecar-b deploy
	make -C deployments/just-sidecar deploy

verify:
	make -C deployments/primary-sidecar-a verify
	make -C deployments/primary-sidecar-b verify
	make -C deployments/just-sidecar verify

generate_vm_scripts:
	make -C deployments/primary-sidecar-a generate_vm_scripts
	make -C deployments/primary-sidecar-b generate_vm_scripts
	make -C deployments/just-sidecar generate_vm_scripts
# Do this so that tar file contains lcow_ folders without extra path components
# before
	tmpdir=$$(mktemp -d) && \
	cd deployments/primary-sidecar-a && \
	cp -r lcow_* $$tmpdir && \
	cd ../primary-sidecar-b && \
	cp -r lcow_* $$tmpdir && \
	cd ../just-sidecar && \
	cp -r lcow_* $$tmpdir && \
	cd ../.. && \
	tar -czf lcows_fragment.tar.gz -C $$tmpdir . && \
	rm -rf $$tmpdir
