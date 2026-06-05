# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the reference:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
project = "RK3588 Video Decode Stack"
copyright = "2026, liyifan"
author = "liyifan"
release = "1.5.0"
version = "1.5.0"

# -- General configuration ---------------------------------------------------
extensions = [
    "myst_parser",
    "sphinx_copybutton",
    "sphinx_togglebutton",
    "sphinx_design",
]

templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store", "venv", "_static"]

# -- Options for MyST --------------------------------------------------------
myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "dollarmath",
    "amsmath",
    "fieldlist",
]
myst_heading_anchors = 3
source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

# -- Options for HTML output -------------------------------------------------
html_theme = "furo"
html_title = "RK3588 Video Decode Stack"
html_short_title = "RK3588 V4L2"
html_theme_options = {
    "navigation_with_keys": True,
    "top_of_page_buttons": ["view", "edit"],
    "source_repository": "https://github.com/pty819/rk3588-video-decode-stack",
    "source_branch": "main",
    "source_directory": "docs/",
}
html_context = {
    "default_mode": "light",
}

# -- Cross-reference information --------------------------------------------
nitpicky = True
nitpick_ignore = []
