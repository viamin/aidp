# Docker Quickstart

Run Aidp with Docker when you do not want a local Ruby toolchain. The image
bundles Aidp and its runtime dependencies; you only provide API keys and a
project mount.

## Build the image

```bash
docker build -t aidp:local .
```

To publish a multi-arch image:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/<org>/aidp:latest \
  --push .
```

## Runtime environment

Aidp never stores provider credentials in the image. Pass them at runtime with
shell env vars or an `.env` file.

Supported env vars commonly used with the Docker image:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GEMINI_API_KEY`
- `GOOGLE_API_KEY`
- `OPENROUTER_API_KEY`
- `GH_TOKEN` or `GITHUB_TOKEN` for read-only `gh` access to private repos

Example `.env`:

```dotenv
ANTHROPIC_API_KEY=...
OPENAI_API_KEY=...
GITHUB_TOKEN=...
```

## Interactive mode

Mount your project at `/workspace` and persist `.aidp` between runs:

```bash
docker run --rm -it \
  --env-file .env \
  -v "$(pwd)":/workspace \
  -v "$(pwd)/.aidp":/workspace/.aidp \
  aidp:local
```

The image entrypoint defaults to interactive `aidp` mode, so no extra command
is required.

If you prefer a repo-local wrapper:

```bash
./docker/aidp
```

## Watch mode

For public repositories:

```bash
docker run --rm -it \
  --env-file .env \
  -v "$(pwd)":/workspace \
  -v "$(pwd)/.aidp":/workspace/.aidp \
  aidp:local watch https://github.com/<owner>/<repo>/issues
```

For private repositories, also pass `GH_TOKEN` or `GITHUB_TOKEN`. The image
includes `gh`, but it only uses the token you provide at runtime.

Wrapper form:

```bash
./docker/aidp-watch https://github.com/<owner>/<repo>/issues
```

## Security defaults

- The container runs as the non-root `aidp` user.
- No SSH agent or host credential directories are mounted by default.
- Secrets stay outside the image unless you explicitly pass them at runtime.

Optional network controls:

- `--network none` blocks all outbound access. Interactive local-only work can
  still run, but provider APIs and GitHub access will fail.
- `--network bridge` keeps Docker defaults.
- Use a custom Docker network if you want stricter egress policy than the
  default bridge.

## Troubleshooting

If the container starts with an empty workspace message, you forgot the project
mount:

```bash
-v "$(pwd)":/workspace
```

If files inside `/workspace` are owned by the wrong UID on Linux, rebuild with a
matching image user or override the runtime user:

```bash
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  --env-file .env \
  -v "$(pwd)":/workspace \
  -v "$(pwd)/.aidp":/workspace/.aidp \
  aidp:local
```
