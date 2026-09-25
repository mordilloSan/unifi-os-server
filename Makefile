NAME    = uos-test
COMPOSE = docker compose -p $(NAME) -f docker-compose.yaml -f docker-compose.test.yaml
VOLUMES = persistent var-log data srv var-lib-unifi var-lib-mongodb etc-rabbitmq-ssl
# Last healthcheck result as one systemd-style line: [  OK  ] or [FAILED]
export HEALTH_JQ = .[0].State.Health | (if .Status == "healthy" then "[\u001b[32m  OK  \u001b[0m]" else "[\u001b[31mFAILED\u001b[0m]" end) + " healthcheck: " + (.Log[-1].Output | rtrimstr("\n") | rtrimstr(" "))

.PHONY: lint test clean distclean

lint:
	shellcheck -S warning uos-entrypoint.sh uos-healthcheck.sh uos-journal-pump.sh uos-failure-dump.sh
	shfmt -d uos-entrypoint.sh uos-healthcheck.sh uos-journal-pump.sh uos-failure-dump.sh
	python3 -c "compile(open('uos-console-journal.py').read(), 'uos-console-journal.py', 'exec')"
	$(COMPOSE) config -q

# Build, boot on ./.test-data (created as your user, so the ownership fix has work to do) and follow
# docker logs until Ctrl+C. The healthcheck result is printed into the stream once it settles.
# The containers keep running afterwards: make clean stops them.
test:
	mkdir -p $(addprefix .test-data/,$(VOLUMES))
	$(COMPOSE) up -d --build
	@echo "--- docker logs, live; healthcheck result follows once it settles (start-period is 5m); Ctrl+C to stop ---"
	@( for i in $$(seq 1 120); do \
		[ "$$(docker inspect -f '{{.State.Health.Status}}' $(NAME))" = starting ] || break; \
		sleep 5; \
	done; docker inspect $(NAME) | jq -r "$$HEALTH_JQ" ) & watch=$$!; \
	trap 'kill $$watch 2>/dev/null' EXIT INT TERM; \
	docker logs -f $(NAME)

# Remove the test container and its network. distclean also wipes ./.test-data, whose files are
# root-owned, so the rm runs in a container.
clean:
	$(COMPOSE) down

distclean: clean
	docker run --rm -v $(CURDIR)/.test-data:/mnt busybox rm -rf $(addprefix /mnt/,$(VOLUMES))
