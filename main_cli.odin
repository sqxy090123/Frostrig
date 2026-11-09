package main

import core "./core"
import algo "./algo"
import fmt "core:fmt"

	Cli_Config :: struct {
		algo_name:    string,
		coin:         string,
		pool_url:     string,
		username:     string,
		password:     string,
		threads:      u32,
		cpu_affinity: string,
		cpu_priority: int,
		no_gui:      bool,
		bench:       bool,
		list_algos:  bool,
		huge_pages:  bool,
	}

	default_cli_config :: proc() -> Cli_Config {
		return Cli_Config{
			threads      = 1,
			cpu_priority = 0,
			huge_pages   = true,
		}
	}

// parse_args walks argv (starting at index 1) and fills Cli_Config.
// Returns an error string when an unknown flag or missing value is found;
// an empty string means success.
parse_args :: proc(argv: []string) -> (config: Cli_Config, err_msg: string) {
	config = default_cli_config()
	i := 1
	for ; i < len(argv); i += 1 {
		err := parse_single_flag(&config, argv, &i)
		if err != "" {
			return {}, err
		}
	}
	if config.threads == 0 {
		config.threads = 1
	}
	return config, ""
}

// parse_single_flag handles one argument at position i (a ^int so the
// caller's index can be advanced past the flag's value).  Returns "" on
// success.
parse_single_flag :: proc(
	config: ^Cli_Config,
	argv:   []string,
	i:      ^int,
) -> string {
	arg := argv[i^]
	if arg == "-a" || arg == "--algo" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for -a/--algo"
		}
		config.algo_name = v
		i^ += 1
	} else if arg == "--coin" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for --coin"
		}
		config.coin = v
		i^ += 1
	} else if arg == "-o" || arg == "--url" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for -o/--url"
		}
		config.pool_url = v
		i^ += 1
	} else if arg == "-u" || arg == "--user" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for -u/--user"
		}
		config.username = v
		i^ += 1
	} else if arg == "-p" || arg == "--pass" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for -p/--pass"
		}
		config.password = v
		i^ += 1
	} else if arg == "-t" || arg == "--threads" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for -t/--threads"
		}
		n, num_ok := parse_u32(v)
		if num_ok == false {
			return fmt.tprintf("invalid thread count: %s", v)
		}
		config.threads = n
		i^ += 1
	} else if arg == "--cpu-affinity" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for --cpu-affinity"
		}
		config.cpu_affinity = v
		i^ += 1
	} else if arg == "--cpu-priority" {
		v, ok := next_value(argv, i^)
		if ok == false {
			return "missing value for --cpu-priority"
		}
		n, num_ok := parse_i32(v)
		if num_ok == false {
			return fmt.tprintf("invalid cpu priority: %s", v)
		}
		config.cpu_priority = int(n)
		i^ += 1
	} else if arg == "--no-gui" {
		config.no_gui = true
	} else if arg == "--bench" {
		config.bench = true
	} else if arg == "--list-algos" {
		config.list_algos = true
	} else if arg == "--no-huge-pages" {
		config.huge_pages = false
	} else {
		if starts_with_dash(arg) {
			return fmt.tprintf("unknown flag: %s", arg)
		}
	}
	return ""
}

// next_value returns the argument immediately after index i.
next_value :: proc(argv: []string, i: int) -> (value: string, ok: bool) {
	if i+1 >= len(argv) {
		return "", false
	}
	return argv[i+1], true
}

// starts_with_dash reports whether s is a non-empty string whose first
// byte is '-'.
starts_with_dash :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}
	return s[0] == '-'
}

// parse_u32 converts a decimal string to u32.
parse_u32 :: proc(s: string) -> (value: u32, ok: bool) {
	if len(s) == 0 {
		return 0, false
	}
	n := 0
	sign := 1
	j := 0
	if s[0] == '-' {
		sign = -1
		j = 1
	}
	if j >= len(s) {
		return 0, false
	}
	for j < len(s) {
		ch := s[j]
		digit := int(ch) - int('0')
		if digit < 0 {
			return 0, false
		}
		if digit > 9 {
			return 0, false
		}
		n = n*10 + digit
		j += 1
	}
	v := n * sign
	if v < 0 {
		return 0, false
	}
	return u32(v), true
}

// parse_i32 converts a decimal string to int.
parse_i32 :: proc(s: string) -> (value: int, ok: bool) {
	if len(s) == 0 {
		return 0, false
	}
	n := 0
	sign := 1
	j := 0
	if s[0] == '-' {
		sign = -1
		j = 1
	}
	if j >= len(s) {
		return 0, false
	}
	for j < len(s) {
		ch := s[j]
		digit := int(ch) - int('0')
		if digit < 0 {
			return 0, false
		}
		if digit > 9 {
			return 0, false
		}
		n = n*10 + digit
		j += 1
	}
	return n * sign, true
}

// resolve_algo looks up the algorithm by name in the registry and returns
// the Algo_Id, or an error string when not found.
resolve_algo :: proc(name: string) -> (id: core.Algo_Id, err_msg: string) {
	entry, ok := algo.lookup_by_name(name)
	if ok == false {
		return core.Algo_Id(0), fmt.tprintf("unknown algorithm: %s", name)
	}
	return entry.id, ""
}

// build_miner_config converts a Cli_Config plus the resolved algo id into
// a core.Miner_Config ready to hand to the worker pool.
	build_miner_config :: proc(cli: Cli_Config, algo_id: core.Algo_Id) -> core.Miner_Config {
		return core.Miner_Config{
			thread_count = cli.threads,
			huge_pages   = cli.huge_pages,
			cpu_affinity = cli.cpu_affinity != "",
			algo         = algo_id,
		}
	}

// list_algos prints every registered algorithm name and its memory
// footprint.
list_algos :: proc() {
	n := algo.count()
	for i in 0 ..< n {
		entry, _ := algo.lookup_by_index(i)
		mb := entry.memory / (1024 * 1024)
		if len(entry.alias) > 0 {
			fmt.printfln("%s (alias: %s)  (memory: %v MB)", entry.name, entry.alias, mb)
		} else {
			fmt.printfln("%s  (memory: %v MB)", entry.name, mb)
		}
	}
}
