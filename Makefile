VENV_PYTHON ?= .venv/bin/python
UNITTEST_DISCOVER ?= discover -s tests -p 'test_*.py' -v
PG_VALIDATE_HOSTED_STRICT ?= 0

.PHONY: check-venv test test-pg-live pg-validate-hosted \	pip-audit \	prod-auth-generate prod-auth-sync-github prod-auth-sync-railway mint-jwt security-provider-audit \
	embedding-seed-jobs embedding-worker-once embedding-worker \
	embedding-autoscaler-once embedding-autoscaler \
	crypto-watcher-once crypto-watcher \
	erpc-up erpc-down erpc-logs erpc-status \
	production-like-validation \
	pgvector-ann-tune \
	bench bench-quick bench-save-baseline bench-compare bench-sweep-contradiction \
	pg-migrate-plan pg-migrate-plan-pgvector \
	pg-migrate-plan-phase3 \
	pg-migrate-up pg-migrate-up-pgvector \
	pg-migrate-up-phase3 \
	pg-migrate-down pg-migrate-down-pgvector \
	pg-migrate-down-phase3 \
	pg-migrate-verify pg-migrate-verify-pgvector \
	pg-migrate-verify-phase3 \
	sync-cli dist-cli

check-venv:
	@if [ ! -x "$(VENV_PYTHON)" ]; then \
		echo "Missing $(VENV_PYTHON)."; \
		echo "Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"; \
		exit 1; \
	fi

test: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m unittest $(UNITTEST_DISCOVER)

pip-audit: check-venv
	$(VENV_PYTHON) -m pip_audit -r requirements-lock.txt --desc

test-pg-live: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m unittest \
		tests.test_pg_store_live_integration \
		tests.test_pg_queue_live_integration \
		tests.test_pg_api_live_integration \
		tests.test_pg_migration_live_integration \
		-v

pg-validate-hosted: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.run_hosted_pg_validation \
		$(if $(filter 1,$(PG_VALIDATE_HOSTED_STRICT)),--strict,)

prod-auth-generate: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) scripts/configure_production_auth.py generate

prod-auth-sync-github: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) scripts/configure_production_auth.py sync-github

prod-auth-sync-railway: check-venv
	@cmd='PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) scripts/configure_production_auth.py sync-railway --environment "$${RAILWAY_ENVIRONMENT:?set RAILWAY_ENVIRONMENT}" --service "$${RAILWAY_SERVICE_1:?set RAILWAY_SERVICE_1}"'; \
	if [ -n "$${RAILWAY_SERVICE_2:-}" ]; then cmd="$$cmd --service \"$$RAILWAY_SERVICE_2\""; fi; \
	if [ -n "$${RAILWAY_SERVICE_3:-}" ]; then cmd="$$cmd --service \"$$RAILWAY_SERVICE_3\""; fi; \
	eval "$$cmd"

mint-jwt: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) scripts/mint_jwt.py \
		--subject "$${JWT_SUBJECT:?set JWT_SUBJECT}"

security-provider-audit: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) scripts/motecloud_security_provider_audit.py

embedding-seed-jobs: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.embedding_seed_jobs \
		--backend postgres \
		--dsn "$${MOTECLOUD_PG_DSN}" \
		--schema "$${MOTECLOUD_PG_SCHEMA:-public}" \
		--enable-persistence

embedding-worker-once: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.embedding_worker \
		--backend postgres \
		--dsn "$${MOTECLOUD_PG_DSN}" \
		--schema "$${MOTECLOUD_PG_SCHEMA:-public}" \
		--enable-persistence \
		--max-cycles 1 \
		--idle-exit-cycles 1 \
		--poll-interval-seconds 0

embedding-worker: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.embedding_worker \
		--backend postgres \
		--dsn "$${MOTECLOUD_PG_DSN}" \
		--schema "$${MOTECLOUD_PG_SCHEMA:-public}" \
		--enable-persistence \
		--idle-exit-cycles 0

embedding-autoscaler-once: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.embedding_autoscaler \
		--backend postgres \
		--dsn "$${MOTECLOUD_PG_DSN}" \
		--schema "$${MOTECLOUD_PG_SCHEMA:-public}" \
		--enable-persistence \
		--max-cycles 1

embedding-autoscaler: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.embedding_autoscaler \
		--backend postgres \
		--dsn "$${MOTECLOUD_PG_DSN}" \
		--schema "$${MOTECLOUD_PG_SCHEMA:-public}" \
		--enable-persistence

crypto-watcher-once: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.crypto_internal_watcher \
		--max-cycles 1 \
		--interval-seconds 0.1

crypto-watcher: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.crypto_internal_watcher

erpc-up:
	docker compose -f ops/erpc/docker-compose.yml up -d

erpc-down:
	docker compose -f ops/erpc/docker-compose.yml down

erpc-logs:
	docker compose -f ops/erpc/docker-compose.yml logs -f erpc

erpc-status:
	docker compose -f ops/erpc/docker-compose.yml ps

production-like-validation: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.run_production_like_validation \
		--require-pass

pgvector-ann-tune: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.tune_pgvector_ann \
		--dsn "$${MOTECLOUD_PG_DSN}" \
		--output research/motecloud-pgvector-ann-tuning-report.md \
		--json-output research/motecloud-pgvector-ann-tuning-results.json

pg-migrate-plan: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations plan --schema "$${MOTECLOUD_PG_SCHEMA:-public}"

pg-migrate-plan-pgvector: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations plan --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-pgvector

pg-migrate-plan-phase3: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations plan --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-phase3

pg-migrate-up: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations up --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}"

pg-migrate-up-pgvector: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations up --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-pgvector

pg-migrate-up-phase3: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations up --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-phase3

pg-migrate-down: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations down --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}"

pg-migrate-down-pgvector: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations down --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-pgvector

pg-migrate-down-phase3: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations down --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-phase3

pg-migrate-verify: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations verify --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}"

pg-migrate-verify-pgvector: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations verify --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --require-pgvector

pg-migrate-verify-phase3: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.manage_pg_migrations verify --dsn "$${MOTECLOUD_PG_DSN}" --schema "$${MOTECLOUD_PG_SCHEMA:-public}" --include-phase3

# ---------------------------------------------------------------------------
# Benchmark suite
# ---------------------------------------------------------------------------

BENCH_BASELINE := research/artifacts/benchmarks/baseline.json
BENCH_OUTPUT := research/artifacts/benchmarks

bench: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.bench \
		--baseline $(BENCH_BASELINE) --output-dir $(BENCH_OUTPUT)

bench-quick: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.bench \
		--tags fast --baseline $(BENCH_BASELINE) --output-dir $(BENCH_OUTPUT)

bench-save-baseline: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.bench \
		--save-baseline --output-dir $(BENCH_OUTPUT)

bench-compare: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.bench \
		--compare $(BENCH_OUTPUT)/latest.json --baseline $(BENCH_BASELINE) \
		--no-markdown --output-dir $(BENCH_OUTPUT)

SWEEP_GRID ?= quick
bench-sweep-contradiction: check-venv
	PYTHONDONTWRITEBYTECODE=1 $(VENV_PYTHON) -m experiments.sweep_contradiction_retrieval \
		--grid $(SWEEP_GRID) --output-dir research/artifacts/experiments/contradiction-sweep

# ---- CLI distribution targets ----
CLI_VERSION ?= v0.2.0

## sync-cli: copy standalone script into the motecloud_cli package (run after editing scripts/motecloud.py)
sync-cli:
	@echo "Syncing scripts/motecloud.py -> motecloud_cli/_core.py ..."
	python3 scripts/sync_cli.py
	@echo "Done."

## dist-cli: repackage the distribution bundle for the current CLI_VERSION
dist-cli: check-venv
	STAGE=dist/motecloud-cli/$(CLI_VERSION); \
	ROOT=dist/motecloud-cli/motecloud-cli-$(CLI_VERSION); \
	VERSION_BARE="$(CLI_VERSION)"; VERSION_BARE=$${VERSION_BARE#v}; \
	TMP_ASSETS=$$(mktemp -d); \
	for file in INSTALL.txt LICENSE.txt RELEASE_NOTES.txt VERIFY.sh; do \
		test -f "$$STAGE/$$file" && cp "$$STAGE/$$file" "$$TMP_ASSETS/$$file" || true; \
	done; \
	rm -rf "$$STAGE" "$$ROOT"; \
	mkdir -p "$$STAGE" "$$ROOT"; \
	cp scripts/motecloud.py scripts/motecloud.sh "$$STAGE"/; \
	cp scripts/motecloud.py scripts/motecloud.sh "$$ROOT"/; \
	printf 'motecloud-cli %s\n' "$$VERSION_BARE" > "$$STAGE"/VERSION; \
	printf 'motecloud-cli %s\n' "$$VERSION_BARE" > "$$ROOT"/VERSION; \
	for file in INSTALL.txt LICENSE.txt RELEASE_NOTES.txt VERIFY.sh; do \
		if test -f "$$TMP_ASSETS/$$file"; then \
			cp "$$TMP_ASSETS/$$file" "$$STAGE/$$file"; \
			cp "$$TMP_ASSETS/$$file" "$$ROOT/$$file"; \
		fi; \
	done; \
	rm -rf "$$TMP_ASSETS"; \
	for file in motecloud.py motecloud.sh; do \
		(cd "$$STAGE" && sha256sum "$$file" > "$$file.sha256"); \
		(cd "$$ROOT" && sha256sum "$$file" > "$$file.sha256"); \
	done; \
	(cd "$$STAGE" && sha256sum * > SHA256SUMS); \
	(cd dist/motecloud-cli && tar -czf motecloud-cli-$(CLI_VERSION).tar.gz motecloud-cli-$(CLI_VERSION)/); \
	sha256sum dist/motecloud-cli/motecloud-cli-$(CLI_VERSION).tar.gz > dist/motecloud-cli/motecloud-cli-$(CLI_VERSION).tar.gz.sha256; \
	rm -rf "$$ROOT"; \
	CLI_VERSION=$(CLI_VERSION) $(VENV_PYTHON) generate_release_assets.py
	@echo "Bundle ready at dist/motecloud-cli/motecloud-cli-$(CLI_VERSION).tar.gz"
