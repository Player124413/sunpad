#include "moderngekko/runtime.hpp"

#include <cassert>

int main()
{
  moderngekko::RuntimeConfig config;
  assert(!config.enable_gmse01_60fps);

  config.enable_gmse01_60fps = true;
  assert(config.enable_gmse01_60fps);
  return 0;
}
