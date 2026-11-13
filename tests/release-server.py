# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

"""Serves the files of a directory over HTTP as GitHub serves release assets.

Usage: release-server.py <directory> <latest tag> <port file>

GitHub redirects /releases/latest to the page of the latest release, whose URL
ends in its tag, or to the list of releases if all of them are prereleases,
which an empty latest tag stands for. The server writes the port it listens on
to the port file once it accepts connections.
"""

import functools
import http.server
import sys


class ReleaseHandler(http.server.SimpleHTTPRequestHandler):
    """Redirects the latest release to its tag and serves the other paths."""

    def __init__(self, *args, latest_tag, **kwargs):
        self.latest_tag = latest_tag
        super().__init__(*args, **kwargs)

    def do_GET(self):
        if self.path == "/releases/latest":
            self.send_response(302)
            if self.latest_tag:
                self.send_header("Location", f"/releases/tag/{self.latest_tag}")
            else:
                self.send_header("Location", "/releases")
            self.end_headers()
        else:
            super().do_GET()

    def do_HEAD(self):
        self.do_GET()

    def log_message(self, format, *args):
        pass


def main():
    directory, latest_tag, port_file = sys.argv[1:]
    handler = functools.partial(ReleaseHandler, directory=directory, latest_tag=latest_tag)

    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        with open(port_file, "w", encoding="utf-8") as file:
            file.write(str(server.server_address[1]))
        server.serve_forever()


if __name__ == "__main__":
    main()
