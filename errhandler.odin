#+feature global-context

package main

import os "core:os"
import io "core:io"

@(init)
errhandler_init :: proc() {
	f, err := os.open("errhandler.log", {.Write, .Append, .Create})
	if err != nil {
		_, _ = io.write_string(os.to_writer(os.stderr), "errhandler: cannot open errhandler.log\n")
		return
	}
	_, _ = io.write_string(os.to_writer(f), "errhandler installed\n")
	os.close(f)
}
