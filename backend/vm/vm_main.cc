#include "vm/chunk.h"
#include "vm/vm.h"

#include <iostream>
#include <string>
#include <string_view>
#include <vector>

namespace {

void print_usage(std::ostream &out) {
  out << "usage: kinglet --run <program.kbc> [args...]\n"
      << "       kinglet <program.kbc> [args...]\n"
      << "\n"
      << "Bytecode VM host for the self-hosted Kinglet compiler.\n"
      << "Compile .kl with bootstrap kinglet or `compiler.kbc`, then execute\n"
      << "via --run. Selfhost suites pass compiler flags after the .kbc path\n"
      << "(e.g. kinglet --run compiler.kbc --ast file.kl).\n";
}

} // namespace

int main(int argc, char **argv) {
  if (argc < 2) {
    print_usage(std::cerr);
    return 64;
  }

  std::string kbc_path;
  std::vector<std::string> program_args;

  for (int i = 1; i < argc; ++i) {
    const std::string_view arg(argv[i]);
    if (arg == "-h" || arg == "--help") {
      print_usage(std::cout);
      return 0;
    }
    if (arg == "--run") {
      if (i + 1 >= argc) {
        std::cerr << "kinglet: --run requires a .kbc file\n";
        return 64;
      }
      kbc_path = argv[++i];
      continue;
    }
    if (kbc_path.empty()) {
      kbc_path = std::string(arg);
      continue;
    }
    program_args.emplace_back(arg);
  }

  if (kbc_path.empty()) {
    print_usage(std::cerr);
    return 64;
  }

  std::string error;
  kinglet::Chunk chunk = kinglet::Chunk::deserialize(kbc_path, &error);
  if (!error.empty()) {
    std::cerr << "kinglet: " << error << "\n";
    return 66;
  }

  kinglet::Vm vm;
  kinglet::VmResult result = vm.run(chunk, program_args);
  if (!result.ok) {
    std::cerr << "runtime error: " << result.error << "\n";
    return 70;
  }

  return kinglet::exit_code_from_value(result.value);
}
