#include "vm/chunk.h"
#include "vm/vm.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <unistd.h>
#include <iostream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

// Embedded self-host compiler bytecode.
#include "vm/embedded_kbc.h"

namespace {

int usage() {
  std::cerr << "usage: kinglet <file.kl|file.kbc> [args...]\n"
            << "       kinglet --save-bytecode <out.kbc> <file.kl>\n"
            << "\n"
            << "Reads Kinglet source from a .kl file, compiles it with the\n"
            << "embedded self-host compiler, and runs the result in the VM.\n"
            << "With a .kbc file, loads and executes it directly.\n";
  return 64;
}

} // namespace

int main(int argc, char **argv) {
  if (argc < 2) return usage();

  std::string save_path;
  int file_arg = 1;

  if (argc >= 4 && std::string_view(argv[1]) == "--save-bytecode") {
    save_path = argv[2];
    file_arg = 3;
  }
  if (file_arg >= argc) return usage();

  std::string input_path = argv[file_arg];
  std::vector<std::string> program_args;
  for (int i = file_arg + 1; i < argc; ++i)
    program_args.emplace_back(argv[i]);

  // ----- .kbc -- load and run directly ----------
  if (input_path.size() >= 4 &&
      input_path.substr(input_path.size() - 4) == ".kbc") {
    std::string error;
    kinglet::Chunk chunk = kinglet::Chunk::deserialize(input_path, &error);
    if (!error.empty()) {
      std::cerr << "kinglet: " << error << "\n";
      return 66;
    }

    if (!save_path.empty()) {
      std::ifstream src(input_path, std::ios::binary);
      std::ofstream dst(save_path, std::ios::binary);
      dst << src.rdbuf();
      return 0;
    }

    kinglet::Vm vm;
    auto result = vm.run(chunk, program_args);
    if (!result.ok) {
      std::cerr << "runtime error: " << result.error << "\n";
      return 70;
    }
    return kinglet::exit_code_from_value(result.value);
  }

  // ----- .kl -- compile with embedded self-host, then run ----------
  std::string error;
  kinglet::Chunk sh_chunk = kinglet::Chunk::deserialize_from_bytes(
      compiler_kbc, compiler_kbc_len, &error);
  if (!error.empty()) {
    std::cerr << "kinglet: corrupt embedded compiler: " << error << "\n";
    return 66;
  }

  // Compile via sh compiler: <input> --save-bytecode <tmp>
  char tmp_name[] = "/tmp/kinglet_sh_XXXXXX";
  int tmp_fd = mkstemp(tmp_name);
  if (tmp_fd < 0) {
    std::cerr << "kinglet: cannot create temp file\n";
    return 74;
  }
  close(tmp_fd);
  std::string tmp_kbc = tmp_name;

  std::vector<std::string> sh_args;
  sh_args.push_back(input_path);
  sh_args.push_back("--save-bytecode");
  sh_args.push_back(tmp_kbc);
  for (const auto &a : program_args) sh_args.push_back(a);

  {
    kinglet::Vm sh_vm;
    auto result = sh_vm.run(sh_chunk, sh_args);
    if (!result.ok) {
      std::cerr << "compile error: " << result.error << "\n";
      std::remove(tmp_kbc.c_str());
      return 70;
    }
    int compile_exit = kinglet::exit_code_from_value(result.value);
    if (compile_exit != 0) {
      std::remove(tmp_kbc.c_str());
      return compile_exit;
    }
  }

  if (!save_path.empty()) {
    std::rename(tmp_kbc.c_str(), save_path.c_str());
    return 0;
  }

  kinglet::Chunk compiled = kinglet::Chunk::deserialize(tmp_kbc, &error);
  std::remove(tmp_kbc.c_str());
  if (!error.empty()) {
    std::cerr << "kinglet: " << error << "\n";
    return 66;
  }

  kinglet::Vm vm;
  auto result = vm.run(compiled, program_args);
  if (!result.ok) {
    std::cerr << "runtime error: " << result.error << "\n";
    return 70;
  }
  return kinglet::exit_code_from_value(result.value);
}
