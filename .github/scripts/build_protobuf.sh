#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROTO_DIR="$REPO_DIR/proto/flipperzero"
OUT_DIR="$REPO_DIR/lib/src/proto/generated"
EXPORT_FILE="$REPO_DIR/lib/protobuf.dart"
PLUGIN_PATH="$HOME/.pub-cache/bin/protoc-gen-dart"

PROTOC_VERSION="${PROTOC_VERSION:-34.1}"
PROTOC_PLUGIN_VERSION="${PROTOC_PLUGIN_VERSION:-25.0.0}"

case "$(uname -m)" in
  x86_64) ARCH="x86_64" ;;
  aarch64 | arm64) ARCH="aarch_64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "[protobuf] protoc ${PROTOC_VERSION} (linux-${ARCH}), protoc_plugin ${PROTOC_PLUGIN_VERSION}"

flutter pub global activate protoc_plugin "$PROTOC_PLUGIN_VERSION"
if [[ ! -x "$PLUGIN_PATH" ]]; then
  echo "protoc-gen-dart not found at $PLUGIN_PATH" >&2
  exit 1
fi

curl -fsSL \
  "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-${ARCH}.zip" \
  -o "$WORK_DIR/protoc.zip"
unzip -oq "$WORK_DIR/protoc.zip" -d "$WORK_DIR/protoc"
PROTOC_BIN="$WORK_DIR/protoc/bin/protoc"
"$PROTOC_BIN" --version

PROTOS=(
  flipper
  storage
  system
  application
  gui
  gpio
  property
  desktop
  network
  gps
)

PROTO_FILES=()
for proto in "${PROTOS[@]}"; do
  PROTO_FILES+=("$PROTO_DIR/$proto.proto")
done

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.pb*.dart

"$PROTOC_BIN" \
  "-I$PROTO_DIR" \
  "--plugin=protoc-gen-dart=$PLUGIN_PATH" \
  "--dart_out=$OUT_DIR" \
  "${PROTO_FILES[@]}"

{
  echo "library;"
  echo
  for proto in "${PROTOS[@]}"; do
    echo "export 'src/proto/generated/${proto}.pb.dart';"
  done
} > "$EXPORT_FILE"

echo "[protobuf] generated into $OUT_DIR"
