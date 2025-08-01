# https://github.com/emqx/emqx-builder
export EMQX_BUILDER_VSN=5.5-5
export OTP_VSN=27.3.4.2-1
export ELIXIR_VSN=1.18.3
export EMQX_BUILDER=ghcr.io/emqx/emqx-builder/${EMQX_BUILDER_VSN}:${ELIXIR_VSN}-${OTP_VSN}-ubuntu24.04
export EMQX_DOCKER_BUILD_FROM=ghcr.io/emqx/emqx-builder/${EMQX_BUILDER_VSN}:${ELIXIR_VSN}-${OTP_VSN}-debian12
export EMQX_DOCKER_RUN_FROM=debian:12-slim
export QUICER_DOWNLOAD_FROM_RELEASE=1
