help([[
This module loads the run-time environment for RRFS ecflow jobs on
the NOAA RDHPC machine Ursa using Intel oneAPI 2024.2.1
]])

whatis([===[Loads the run-time environment for RRFS ecflow jobs on Ursa ]===])

prepend_path("MODULEPATH", "/contrib/spack-stack/spack-stack-1.9.3/envs/ue-oneapi-2024.2.1/install/modulefiles/Core")
load(pathJoin("stack-oneapi", os.getenv("stack_oneapi_ver") or "2024.2.1"))
load(pathJoin("stack-intel-oneapi-mpi", os.getenv("stack_impi_ver") or "2021.13"))
load(pathJoin("intel-oneapi-mkl", os.getenv("mkl_ver") or "2024.2.1"))

-- Shared libraries the RRFS executables link, at the versions build_ursa_intel.lua builds against
load(pathJoin("zlib", os.getenv("zlib_ver") or "1.2.13"))
load(pathJoin("libpng", os.getenv("libpng_ver") or "1.6.37"))
load(pathJoin("libjpeg", os.getenv("libjpeg_ver") or "2.1.0"))
load(pathJoin("jasper", os.getenv("jasper_ver") or "2.0.32"))
load(pathJoin("hdf5", os.getenv("hdf5_ver") or "1.14.3"))
load(pathJoin("netcdf-c", os.getenv("netcdf_c_ver") or "4.9.2"))
load(pathJoin("netcdf-fortran", os.getenv("netcdf_fortran_ver") or "4.6.1"))
load(pathJoin("parallel-netcdf", os.getenv("pnetcdf_ver") or "1.12.3"))
load(pathJoin("parallelio", os.getenv("pio_ver") or "2.6.2"))
load(pathJoin("esmf", os.getenv("esmf_ver") or "8.8.0"))
load(pathJoin("g2c", os.getenv("g2c_ver") or "2.1.0"))
load(pathJoin("crtm", os.getenv("crtm_ver") or "2.4.0.1"))
load(pathJoin("udunits", os.getenv("udunits_ver") or "2.2.28"))
load(pathJoin("gsl", os.getenv("gsl_ver") or "2.8"))

-- Utilities the job scripts call (prod_util provides compath.py, ndate, cpreq, err_chk, ...)
load(pathJoin("prod_util", os.getenv("prod_util_ver") or "2.1.1"))
load(pathJoin("nco", os.getenv("nco_ver") or "5.2.4"))
load(pathJoin("wgrib2", os.getenv("wgrib2_ver") or "3.6.0"))
load(pathJoin("grib-util", os.getenv("grib_util_ver") or "1.4.0"))

-- Python for the ush/ helpers. lib/raymond.so (blending) is built with this python and numpy,
-- so it must be imported with them too.
load(pathJoin("stack-python", os.getenv("stack_python_ver") or "3.11.7"))
load("py-numpy")
load("py-netcdf4")
load("py-pyyaml")
load("py-jinja2")
load("py-f90nml")
load("py-xarray")
load("py-scipy")
load("py-pandas")
load("py-matplotlib")
