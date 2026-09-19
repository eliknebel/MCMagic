#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
TEST_BUILD_DIR=$(mktemp -d /private/tmp/mcmagic-tests.XXXXXX)
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT

xcrun clang \
    -fobjc-arc \
    -framework Foundation \
    -framework AppKit \
    -framework ApplicationServices \
    -framework CoreGraphics \
    -I "$PROJECT_DIR/MCMagic" \
    "$PROJECT_DIR/MCMagic/MissionControlDetector.m" \
    "$SCRIPT_DIR/MissionControlDetectorTests.m" \
    -o "$TEST_BUILD_DIR/MissionControlDetectorTests"

"$TEST_BUILD_DIR/MissionControlDetectorTests"

xcrun clang \
    -fobjc-arc \
    -framework Foundation \
    -I "$PROJECT_DIR/MCMagic" \
    "$PROJECT_DIR/MCMagic/SwipeGestureClassifier.m" \
    "$SCRIPT_DIR/SwipeGestureClassifierTests.m" \
    -o "$TEST_BUILD_DIR/SwipeGestureClassifierTests"

"$TEST_BUILD_DIR/SwipeGestureClassifierTests"

xcrun clang \
    -fobjc-arc \
    -framework Foundation \
    -I "$PROJECT_DIR/MCMagic" \
    "$PROJECT_DIR/MCMagic/SwipeGestureClassifier.m" \
    "$PROJECT_DIR/MCMagic/SwipeGestureRouter.m" \
    "$SCRIPT_DIR/SwipeGestureRouterTests.m" \
    -o "$TEST_BUILD_DIR/SwipeGestureRouterTests"

"$TEST_BUILD_DIR/SwipeGestureRouterTests"

xcrun clang \
    -fobjc-arc \
    -framework Foundation \
    -I "$PROJECT_DIR/MCMagic" \
    "$PROJECT_DIR/MCMagic/LifecycleRecovery.m" \
    "$SCRIPT_DIR/LifecycleRecoveryTests.m" \
    -o "$TEST_BUILD_DIR/LifecycleRecoveryTests"

"$TEST_BUILD_DIR/LifecycleRecoveryTests"
