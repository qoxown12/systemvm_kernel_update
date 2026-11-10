#!/usr/bin/env python3
"""Small, standard-library-only helpers for the Debian kernel bundle builder."""
import hashlib
import pathlib
import re
import subprocess
import sys
from html.parser import HTMLParser


class Rows(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            self.row.append(" ".join("".join(self.cell).split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def fields(control):
    result = {}
    key = None
    for line in control.splitlines():
        if line.startswith((" ", "\t")) and key:
            result[key] += "\n" + line
        elif ":" in line:
            key, value = line.split(":", 1)
            result[key] = value.strip()
    return result


def tracker(path):
    html = pathlib.Path(path).read_text()
    if "<title>CVE-2026-43499</title>" not in html:
        raise ValueError("Unexpected CVE tracker page")
    parser = Rows()
    parser.feed(html)
    versions = [r[3] for r in parser.rows
                if len(r) >= 4 and r[:3] == ["linux", "source", "bookworm"]]
    if len(versions) != 1 or not re.fullmatch(r"6\.1\.\d+-[0-9A-Za-z.+~]+", versions[0]):
        raise ValueError("Cannot identify a unique fixed bookworm/linux version; refusing to continue")
    print(versions[0])


def index(bundle):
    bundle = pathlib.Path(bundle)
    repo = bundle / "repo"
    records = []
    seen = set()
    for path in sorted(repo.glob("*.deb")):
        control = subprocess.check_output(["dpkg-deb", "--field", str(path)], text=True)
        item = fields(control)
        if item["Architecture"] not in ("amd64", "all"):
            raise ValueError(f"Unexpected architecture in {path.name}")
        identity = (item["Package"], item["Version"], item["Architecture"])
        if identity in seen:
            raise ValueError(f"Duplicate package identity: {identity}")
        seen.add(identity)
        # .deb control files have no repository transport fields.
        if any(k in item for k in ("Filename", "Size", "SHA256")):
            raise ValueError(f"Unexpected repository fields in {path.name}")
        digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
        entry = (control.rstrip() + f"\nFilename: ./{path.name}\nSize: {path.stat().st_size}"
                 + f"\nSHA256: {digest}\n\n")
        records.append((item, path.name, entry))
    if not records:
        raise ValueError("No Debian packages downloaded")
    (repo / "Packages").write_text("".join(r[2] for r in records))
    with (bundle / "packages.tsv").open("w") as manifest:
        manifest.write("Package\tVersion\tArchitecture\tFile\tInstalled-Size-KiB\n")
        for item, name, _ in records:
            manifest.write("\t".join([item["Package"], item["Version"], item["Architecture"],
                                      name, item.get("Installed-Size", "0")]) + "\n")
    kernels = [r[0] for r in records if re.fullmatch(r"linux-image-6\.1\.0-\d+-amd64", r[0]["Package"])]
    metas = [r[0] for r in records if r[0]["Package"] == "linux-image-amd64"]
    if len(kernels) != 1 or len(metas) != 1:
        raise ValueError("Expected one bookworm generic amd64 kernel and one metapackage")
    kernel, meta = kernels[0], metas[0]
    if kernel["Version"] != meta["Version"]:
        raise ValueError("Kernel/metapackage version mismatch")
    if not kernel.get("Source", "").startswith(("linux-signed-amd64 (", "linux (")):
        raise ValueError("Unexpected kernel source package")
    for name, value in (("kernel-package.txt", kernel["Package"]),
                        ("kernel-version.txt", kernel["Version"]),
                        ("meta-version.txt", meta["Version"])):
        (bundle / name).write_text(value + "\n")
    print(f"{len(records)} packages; {kernel['Package']}={kernel['Version']}")


if __name__ == "__main__":
    try:
        {"tracker": tracker, "index": index}[sys.argv[1]](sys.argv[2])
    except (ValueError, KeyError, IndexError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"ERROR: {error}")
