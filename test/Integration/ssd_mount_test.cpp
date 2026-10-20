#include "ssd_mount.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

static int fails = 0;

static void expect(bool cond, const char *msg) {
  if (!cond) {
    std::cerr << "FAIL " << msg << "\n";
    ++fails;
  }
}

int main() {
  expect(unescapeMount("foo\\040bar") == "foo bar", "unescape space");
  expect(unescapeMount("plain") == "plain", "unescape plain");
  expect(mountOption("rw,upperdir=/a/b,lowerdir=/c", "upperdir") == "/a/b",
         "upperdir");
  expect(mountOption("rw,upperdir=/a\\040b", "upperdir") == "/a b",
         "upperdir space");
  expect(mountCovers("/", "/tmp"), "root covers");
  expect(mountCovers("/var", "/var/tmp"), "prefix covers");
  expect(!mountCovers("/var", "/varfoo"), "prefix boundary");
  expect(mountCovers("/var", "/var"), "exact");
  expect(!mountCovers("/", "relative"), "relative not covered by root");

  expect(normalizeSsdDir("/tmp/", "/unused") == "/tmp", "strip slash");
  expect(normalizeSsdDir("/", "/unused") == "/", "keep root");
  expect(normalizeSsdDir("tiles", "/work") == "/work/tiles", "relative");
  expect(normalizeSsdDir("a/../b", "/work") == "/work/b", "dotdot");
  expect(normalizeSsdDir("../b", "/work/sub") == "/work/b", "parent");

  const char *nvmeRoot =
      "10 1 259:1 / / rw - ext4 /dev/nvme0n1p2 rw";
  SsdMount root = describeDir("/tmp", nvmeRoot);
  expect(root.fstype == "ext4", "nvme root fstype");
  expect(root.source == "/dev/nvme0n1p2", "nvme root source");
  expect(root.nvme, "nvme root flag");
  expect(root.fdPath.empty(), "nvme root has no fd path");

  const char *overlayNvme =
      "50 1 0:45 / / rw,relatime - overlay overlay "
      "rw,lowerdir=/lower,upperdir=/mnt/nvme/upper,workdir=/mnt/nvme/work\n"
      "51 50 259:1 / /mnt/nvme rw,relatime - ext4 /dev/nvme1n1p1 rw\n";
  SsdMount over = describeDir("/var/lib/s2c2", overlayNvme);
  expect(over.nvme, "overlay upper on nvme");
  expect(over.source == "/dev/nvme1n1p1", "overlay source");
  expect(over.fstype == "ext4", "overlay fstype");
  expect(over.fdPath == "/mnt/nvme/upper/var/lib/s2c2", "overlay fd path");

  const char *overlayOnly =
      "50 1 0:45 / / rw - overlay overlay "
      "rw,lowerdir=/lower,upperdir=/upper,workdir=/work\n";
  SsdMount only = describeDir("/var/lib/s2c2", overlayOnly);
  expect(!only.nvme, "overlay alone is not nvme");
  expect(only.fstype == "overlay", "overlay fstype stays");
  expect(only.source == "overlay", "overlay source stays");
  expect(only.fdPath == "/upper/var/lib/s2c2", "overlay fd path still set");

  const char *spaced =
      "12 1 8:1 / /tmp/foo\\040bar rw - ext4 /dev/vdc rw\n";
  SsdMount space = describeDir("/tmp/foo bar/x", spaced);
  expect(space.fstype == "ext4", "escaped mount point");
  expect(space.source == "/dev/vdc", "escaped mount source");

  SsdMount missing = describeDir("/tmp", "");
  expect(missing.fstype == "unknown" && missing.source == "unknown", "empty");
  expect(!missing.nvme, "empty not nvme");

  std::ifstream live("/proc/self/mountinfo");
  std::ostringstream text;
  text << live.rdbuf();
  std::string cwd = std::filesystem::current_path().string();
  SsdMount here = describeDir(normalizeSsdDir(".", cwd), text.str());
  expect(here.fstype != "unknown", "live cwd mount");

  if (fails) {
    std::cerr << fails << " failed\n";
    return 1;
  }
  std::cout << "ssd-mount PASS\n";
  return 0;
}
