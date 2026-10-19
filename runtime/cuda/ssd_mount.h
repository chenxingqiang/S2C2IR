//===- ssd_mount.h - storage-pipeline mount lookup (no CUDA) -------------===//
//
// Host-side path and mountinfo helpers for --ssd-dir. The default
// storage pipeline does not call these. A buffered read is not a disk.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_RUNTIME_CUDA_SSD_MOUNT_H
#define S2C2_RUNTIME_CUDA_SSD_MOUNT_H

#include <cctype>
#include <filesystem>
#include <string>

struct SsdMount {
  std::string path;
  std::string fdPath;
  std::string fstype;
  std::string source;
  bool nvme = false;
};

inline std::string unescapeMount(const std::string &in) {
  std::string out;
  for (size_t i = 0; i < in.size(); ++i) {
    if (in[i] == '\\' && i + 3 < in.size() &&
        std::isdigit(static_cast<unsigned char>(in[i + 1])) &&
        std::isdigit(static_cast<unsigned char>(in[i + 2])) &&
        std::isdigit(static_cast<unsigned char>(in[i + 3]))) {
      int v = (in[i + 1] - '0') * 64 + (in[i + 2] - '0') * 8 + (in[i + 3] - '0');
      out.push_back(static_cast<char>(v));
      i += 3;
    } else {
      out.push_back(in[i]);
    }
  }
  return out;
}

inline std::string mountOption(const std::string &super, const char *key) {
  std::string needle = std::string(key) + "=";
  auto pos = super.find(needle);
  if (pos == std::string::npos)
    return {};
  auto start = pos + needle.size();
  auto end = super.find(',', start);
  return unescapeMount(super.substr(start, end == std::string::npos
                                                 ? std::string::npos
                                                 : end - start));
}

inline bool mountCovers(const std::string &point, const std::string &path) {
  if (point == "/")
    return !path.empty() && path[0] == '/';
  if (path == point)
    return true;
  return path.size() > point.size() &&
         path.compare(0, point.size(), point) == 0 &&
         path[point.size()] == '/';
}

// Resolve a --ssd-dir value before mount lookup. A relative directory
// is joined to cwd. The root stays `/`. The path does not have to exist.
inline std::string normalizeSsdDir(const std::string &dir, const std::string &cwd) {
  if (dir.empty())
    return {};
  std::filesystem::path path(dir);
  if (path.is_relative()) {
    if (cwd.empty())
      return {};
    path = std::filesystem::path(cwd) / path;
  }
  path = path.lexically_normal();
  std::string out = path.generic_string();
  while (out.size() > 1 && out.back() == '/')
    out.pop_back();
  return out;
}

// mountinfo is the text of /proc/self/mountinfo. followOverlay looks
// through one overlay upperdir when that path sits on a longer mount.
inline SsdMount describeDir(const std::string &dir, const std::string &mountinfo,
                            bool followOverlay = true) {
  SsdMount info;
  info.path = dir;
  size_t best = 0;
  bool found = false;
  std::string bestSuper;
  size_t lineStart = 0;
  while (lineStart <= mountinfo.size()) {
    size_t lineEnd = mountinfo.find('\n', lineStart);
    if (lineEnd == std::string::npos)
      lineEnd = mountinfo.size();
    std::string line = mountinfo.substr(lineStart, lineEnd - lineStart);
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    lineStart = lineEnd + 1;
    if (line.empty() && lineEnd == mountinfo.size())
      break;
    auto sep = line.find(" - ");
    if (sep == std::string::npos)
      continue;
    std::string left = line.substr(0, sep);
    std::string right = line.substr(sep + 3);
    std::string point;
    {
      std::string field;
      int idx = 0;
      for (size_t i = 0; i <= left.size(); ++i) {
        if (i == left.size() || left[i] == ' ') {
          if (idx == 4)
            point = unescapeMount(field);
          field.clear();
          if (i != left.size())
            ++idx;
        } else {
          field.push_back(left[i]);
        }
      }
    }
    if (!mountCovers(point, dir) || point.size() < best)
      continue;
    std::string fstype;
    std::string source;
    std::string super;
    {
      std::string field;
      int idx = 0;
      for (size_t i = 0; i <= right.size(); ++i) {
        if (i == right.size() || right[i] == ' ') {
          if (idx == 0)
            fstype = field;
          else if (idx == 1)
            source = unescapeMount(field);
          else if (idx == 2)
            super = field;
          field.clear();
          if (i != right.size())
            ++idx;
        } else {
          field.push_back(right[i]);
        }
      }
    }
    best = point.size();
    found = true;
    info.fstype = fstype;
    info.source = source;
    bestSuper = super;
    if (lineEnd == mountinfo.size())
      break;
  }
  if (!found) {
    info.fstype = "unknown";
    info.source = "unknown";
  }
  std::string probe = dir;
  if (info.fstype == "overlay") {
    std::string upper = mountOption(bestSuper, "upperdir");
    if (!upper.empty()) {
      std::string rel = dir;
      if (!rel.empty() && rel[0] == '/')
        rel.erase(rel.begin());
      if (!upper.empty() && upper.back() != '/')
        upper.push_back('/');
      probe = upper + rel;
      info.fdPath = probe;
    }
  }
  if (info.source.find("nvme") != std::string::npos)
    info.nvme = true;
  if (followOverlay && !info.nvme && info.fstype == "overlay" && !probe.empty() &&
      probe != dir) {
    SsdMount under = describeDir(probe, mountinfo, false);
    if (under.nvme || under.source.find("nvme") != std::string::npos) {
      info.source = under.source;
      info.fstype = under.fstype;
      info.nvme = true;
    }
  }
  return info;
}

#endif
