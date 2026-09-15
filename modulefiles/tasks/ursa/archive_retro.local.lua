-- Put the HPSS clients (hsi, htar) on PATH for the retro archive task. Ursa has no hpss module,
-- and rocoto jobs don't get /apps/hpss on PATH by default.
prepend_path("PATH", "/apps/hpss")
load("python_srw")
