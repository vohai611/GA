GAStartupMessage <- function()
{
# Startup message obtained as 
# > figlet GA
  msg <- c(paste0(
"This is MODIFIED version of GA, which message the iteration instead of print, use with care
  ____    _    
 / ___|  / \\     Genetic 
| |  _  / _ \\    Algorithms
| |_| |/ ___ \\   
 \\____/_/   \\_\\  version ", packageVersion("GA")),
"\nType 'citation(\"GA\")' for citing this R package in publications.")
  return(msg)
}

.onAttach <- function(lib, pkg)
{
  # unlock .ga.default variable allowing its modification
  unlockBinding(".ga.default", asNamespace("GA")) 
  # startup message
  msg <- GAStartupMessage()
  if(interactive())
    msg[1] <- paste("Package 'GA' version", packageVersion("GA"))
  packageStartupMessage(msg)
  invisible()
}
