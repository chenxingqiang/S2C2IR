#include "ssd_mount.h"

#include <iostream>
#include <string>

int main() {
  const char octal[] = {'\\', '0', '4', '0', '\0'};
  if (unescapeMount(octal) != " ")
    return 1;
  if (unescapeMount("tmp") != "tmp")
    return 1;
  std::cout << "ssd-unescape PASS\n";
  return 0;
}
