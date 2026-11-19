# The store pictures' goldens are drawn on Linux on x86-64, as CI draws them: fonts
# come out a little differently on every system, and a golden made on a Mac would
# fail on CI. This is the same Flutter, in the same kind of machine.
#
# Built and run by tool/store_shots.sh; FLUTTER is the version from app/.fvmrc.
FROM ubuntu:24.04

# tzdata: the tests run in Europe/Berlin, a zone with clock changes, and without the
# zone's data TZ has no effect (test/flutter_test_config.dart refuses to run then).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils libglu1-mesa tzdata \
 && rm -rf /var/lib/apt/lists/*

ARG FLUTTER
RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER}-stable.tar.xz" \
    | tar -xJ -C /opt \
 && git config --global --add safe.directory /opt/flutter \
 && /opt/flutter/bin/flutter --disable-analytics \
 && /opt/flutter/bin/flutter precache --no-android --no-ios --no-web \
      --no-linux --no-windows --no-macos --no-fuchsia

ENV PATH="/opt/flutter/bin:${PATH}" \
    TZ=Europe/Berlin \
    CI=true
