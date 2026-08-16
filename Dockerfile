FROM rocker/r-ver:4.6.0

# ---- 1. System dependencies -------------------------------------------------
# Covers the headers needed to *compile* the packages in renv.lock
# (curl, ssl, xml2, fonts/harfbuzz for text shaping, V8 for the V8 R package,
# git for renv/remotes installs from GitHub, etc).
# If renv::restore() below fails on a missing header, add the matching
# -dev package here and rebuild — the error message names the library.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pandoc \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgit2-dev \
    libv8-dev \
    libsodium-dev \
    zlib1g-dev \
    texlive-xetex \
    texlive-latex-recommended \
    texlive-latex-extra \
    texlive-lang-german \
    texlive-fonts-recommended \
    texlive-plain-generic \
    lmodern \
    && rm -rf /var/lib/apt/lists/*

# ---- 2. Quarto CLI (system-wide, fine to install as root) --------------------
# TARGETARCH is auto-populated by Docker's BuildKit builder to match
# whatever machine `docker build` runs on (amd64 on your Fedora box,
# arm64 on Apple Silicon) — no manual flag needed on either side.
ARG QUARTO_VERSION=1.7.31
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) QUARTO_ARCH="linux-amd64" ;; \
      arm64) QUARTO_ARCH="linux-arm64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -Lo /tmp/quarto.deb \
      "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-${QUARTO_ARCH}.deb" \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/quarto.deb \
    && rm -rf /tmp/quarto.deb /var/lib/apt/lists/*

# ---- 3. Create the non-root user -------------------------------------
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} rstudio || true \
    && useradd -m -u ${UID} -g ${GID} rstudio || true

WORKDIR /project
RUN chown rstudio:rstudio /project
USER rstudio

# ---- 4. R environment ---------------------------------------------------------
# Keep renv's package library OUTSIDE /project. This is the key to making
# live development work: /project gets bind-mounted with your local repo
# at runtime, which would otherwise silently wipe out the library if it
# lived inside /project (as renv does by default).
# Uses the rstudio user's own home directory (already owned by rstudio,
# unlike /opt which is root-owned and would fail here since we're
# running as rstudio by this point).
ENV RENV_PATHS_LIBRARY=/home/rstudio/.renv-library

# Copy only the files renv needs first, so this expensive layer is cached
# and doesn't get invalidated every time you change an .R or .qmd file.
COPY --chown=rstudio:rstudio .Rprofile renv.lock ./
COPY --chown=rstudio:rstudio renv/activate.R renv/settings.json renv/

RUN R -e "options(renv.consent = TRUE); renv::restore()"

# ---- 5. Project files -----------------------------------------------------
# Baked in as a fallback snapshot so the image works standalone if you
# DON'T mount anything. At runtime, mounting your live repo over /project
# (see README/usage notes) overrides these with your current work.
COPY --chown=rstudio:rstudio . .

CMD ["sh", "-c", "quarto render index.qmd --to pdf"]
