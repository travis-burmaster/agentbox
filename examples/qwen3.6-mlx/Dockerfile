# Extends agentbox:latest with the GitHub CLI (gh) plus vim and nano editors
# for in-container file edits.
#
# Build:
#   (from repo root, one-time) docker build -t agentbox:latest .
#   (from this dir)            docker compose build
#
# The base image already has curl, ca-certificates, and supervisord. We only
# add gh's official apt repo + the gh package, then return to the non-root
# agentbox user.

FROM agentbox:latest

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends gnupg \
 && mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh vim nano \
 && apt-get purge -y --auto-remove gnupg \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

USER agentbox
