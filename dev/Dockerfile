FROM debian:trixie

ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# Install system packages
RUN apt-get update && apt-get install -y \
    bison \
    build-essential \
    ca-certificates \
    curl \
    flex \
    gh \
    git \
    just \
    libopenmpi-dev \
    neovim \
    unzip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Create dev user with bash
RUN useradd -m -s /bin/bash dev

# Switch to dev user
USER dev
WORKDIR /home/dev

# Setup PATH in .bashrc
RUN echo 'export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"' >> ~/.bashrc

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install bun
RUN curl -fsSL https://bun.sh/install | bash

# Install Claude Code (standalone binary)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Python via uv (3.14 as default)
RUN ~/.local/bin/uv python install 3.14 && ln -s $(~/.local/bin/uv python find 3.14) ~/.local/bin/python

# Setup configs (nvim, shell aliases, gitconfig)
RUN git clone https://github.com/c4ffein/c4ffein-configs.git /tmp/c4ffein-configs && \
    mkdir -p ~/.config/nvim ~/.local && \
    cp -r /tmp/c4ffein-configs/home/.config/nvim/* ~/.config/nvim/ && \
    cp /tmp/c4ffein-configs/home/.local/env.sh ~/.local/env.sh && \
    cp /tmp/c4ffein-configs/home/.gitconfig ~/.gitconfig && \
    rm -rf /tmp/c4ffein-configs

# Source shell aliases
RUN echo '[ -f "$HOME/.local/env.sh" ] && . "$HOME/.local/env.sh"' >> ~/.bashrc


# Source .bashrc on login shells too
RUN echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"' >> ~/.profile

CMD ["/bin/bash"]
