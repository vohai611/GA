##############################################################################
#                                                                            #
#                  ISLANDS GENETIC ALGORITHMS in R                           #
#                                                                            #
##############################################################################

gaisl <- function(type = c("binary", "real-valued", "permutation"), 
                  fitness, ...,
                  lower, upper, nBits,
                  population = gaControl(type)$population,
                  selection = gaControl(type)$selection,
                  crossover = gaControl(type)$crossover, 
                  mutation = gaControl(type)$mutation,
                  popSize = 100, 
                  numIslands = 4,
                  migrationRate = 0.10, 
                  migrationInterval = 10,
                  pcrossover = 0.8, 
                  pmutation = 0.1, 
                  elitism = base::max(1, round(popSize/numIslands*0.05)), 
                  updatePop = FALSE,
                  postFitness = NULL,
                  maxiter = 1000,
                  run = maxiter,
                  maxFitness = Inf,
                  names = NULL,
                  suggestions = NULL, 
                  optim = FALSE,
                  optimArgs = list(method = "L-BFGS-B", 
                                   poptim = 0.05,
                                   pressel = 0.5,
                                   control = list(fnscale = -1, maxit = 100)),
                  parallel = TRUE,
                  monitor = if(interactive()) gaislMonitor else FALSE,
                  seed = NULL)
{

  call <- match.call()
  
  type <- match.arg(type, choices = eval(formals(gaisl)$type))
  
  if(!is.function(population)) population <- get(population)
  if(!is.function(selection))  selection  <- get(selection)
  if(!is.function(crossover))  crossover  <- get(crossover)
  if(!is.function(mutation))   mutation   <- get(mutation)
  
  if(missing(fitness))
    { stop("A fitness function must be provided") }
  if(!is.function(fitness)) 
    { stop("A fitness function must be provided") }
  if(popSize < 10) 
    { warning("The population size is less than 10.") }
  if(maxiter < 1) 
    { stop("The maximum number of iterations must be at least 1.") }
  if(elitism > popSize) 
    { stop("The elitism cannot be larger that population size.") }
  elitism <- as.integer(elitism)
  if(pcrossover < 0 | pcrossover > 1)
    { stop("Probability of crossover must be between 0 and 1.") }
  if(is.numeric(pmutation))
    { if(pmutation < 0 | pmutation > 1)
        { stop("If numeric probability of mutation must be between 0 and 1.") }
      else if(!is.function(population))
             { stop("pmutation must be a numeric value in (0,1) or a function.") }
  }
  
  # check for min and max arguments instead of lower and upper
  callArgs <- list(...)
  if(any("min" %in% names(callArgs)))
  {
    lower <- callArgs$min
    callArgs$min <- NULL
    warning("'min' arg is deprecated. Use 'lower' instead.")
  }
  if(any("max" %in% names(callArgs)))
  {
    upper <- callArgs$max
    callArgs$max <- NULL
    warning("'max' arg is deprecated. Use 'upper' instead.")
  }

  if(missing(lower) & missing(upper) & missing(nBits))
    { stop("A lower and upper range of values (for 'real-valued' or 'permutation' GA) or nBits (for 'binary' GA) must be provided!") }
  
  # check GA search type 
  switch(type, 
         "binary"      = { nBits <- as.vector(nBits)[1]
                           lower <- upper <- NA
                           nvars <- nBits 
                           if(is.null(names))
                             names <- paste0("x", 1:nvars)
                         },
         "real-valued" = { lnames <- names(lower)
                           unames <- names(upper)
                           lower <- as.vector(lower)
                           upper <- as.vector(upper)
                           nBits <- NA
                           if(length(lower) != length(upper))
                             stop("lower and upper must be vector of the same length!")
                           nvars <- length(upper)
                           if(is.null(names) & !is.null(lnames))
                             names <- lnames
                           if(is.null(names) & !is.null(unames))
                             names <- unames
                           if(is.null(names))
                             names <- paste0("x", 1:nvars)
                         },
         "permutation" = { lower <- as.vector(lower)[1]
                           upper <- as.vector(upper)[1]
                           nBits <- NA
                           nvars <- length(seq(lower,upper))
                           if(is.null(names))
                             names <- paste0("x", 1:nvars)
                         }
        )

  # check suggestions
  if(is.null(suggestions))
    { suggestions <- matrix(nrow = 0, ncol = nvars) }
  else
    { if(is.vector(suggestions)) 
        { if(nvars > 1) suggestions <- matrix(suggestions, nrow = 1)
          else          suggestions <- matrix(suggestions, ncol = 1) }
      else
        { suggestions <- as.matrix(suggestions) }
      if(nvars != ncol(suggestions))
        stop("Provided suggestions (ncol) matrix do not match number of variables of the problem!")
      ng <- min(nrow(suggestions), popSize)
      suggestions <- suggestions[seq(ng),,drop=FALSE]
    }

  # check monitor arg
  if(is.logical(monitor))
    { if(monitor) monitor <- gaislMonitor }
  if(is.null(monitor)) monitor <- FALSE
  
  islSize <- max(10, floor(popSize/numIslands))
  migPop <- max(1, floor(migrationRate*islSize))
  numiter <- max(1, floor(maxiter/migrationInterval))

  # Start parallel computing (if needed)
  if(is.logical(parallel))
    { if(parallel) 
        { parallel <- startParallel(numIslands)
          stopCluster <- TRUE }
      else
      { parallel <- stopCluster <- FALSE } 
    }
  else
    { stopCluster <- if(inherits(parallel, "cluster")) FALSE else TRUE
      parallel <- startParallel(parallel) 
    }
  on.exit(if(parallel & stopCluster)
          stopParallel(attr(parallel, "cluster")) )
  # define operator to use depending on parallel being TRUE or FALSE
  # `%DO%` <- if(parallel) `%dorng%` else `%do%`
  `%DO%` <- if(parallel && requireNamespace("doRNG", quietly = TRUE)) 
                               doRNG::`%dorng%`
            else if(parallel) `%dopar%` else `%do%`
  # set seed for reproducibility    
  if(!is.null(seed)) set.seed(seed)
  i. <- NULL # dummy to trick R CMD check 
  
  object <- new("gaisl", 
                call = call, 
                type = type,
                lower = lower, 
                upper = upper, 
                nBits = nBits, 
                names = if(is.null(names)) character() else names,
                popSize = popSize,
                numIslands = numIslands,
                migrationRate = migrationRate,
                migrationInterval = migrationInterval,
                maxiter = maxiter,
                run = run, 
                suggestions = suggestions,
                elitism = elitism, 
                pcrossover = pcrossover, 
                pmutation = pmutation,
                optim = optim,
                islands = list(),
                summary = list(),
                fitnessValues = list(),
                solutions = list())
  
  # initialise
  GAs <- vector(mode = "list", length = numIslands)
  POPs <- vector(mode = "list", length = numIslands)
  # POPs <- rep(list(suggestions), times = numIslands)
  if(nrow(suggestions) > 0)
  {
    # POPs <- split.data.frame(suggestions, 
    #                          rep(seq(numIslands), 
    #                              each = floor(nrow(suggestions)/numIslands)))
    POPs <- rep(list(suggestions), numIslands)
  }
  sumryStat <- rep(list(matrix(as.double(NA), 
                               nrow = numiter*migrationInterval, ncol = 6, 
                               dimnames = list(NULL, 
                                               names(gaSummary(rnorm(10)))))), 
                   numIslands)

  for(iter in seq_len(numiter))
  {
    # GA evolution in islands
    GAs <- foreach(i. = seq_len(numIslands)) %DO%
                   # .options.multicore = list(set.seed = seed)
                  { ga(type = type, 
                       fitness = fitness, ...,
                       lower = lower, upper = upper, nBits = nBits,
                       suggestions = POPs[[i.]],
                       population = population,
                       selection = selection, 
                       crossover = crossover, 
                       mutation = mutation, 
                       popSize = islSize, 
                       pcrossover = pcrossover,
                       pmutation = pmutation,
                       elitism = elitism, 
                       updatePop = updatePop,
                       postFitness = postFitness,
                       maxiter = migrationInterval, 
                       run = migrationInterval, 
                       maxFitness = maxFitness, 
                       names = names,
                       optim = optim,
                       optimArgs = optimArgs,
                       keepBest = FALSE, 
                       parallel = FALSE, 
                       monitor = FALSE,
                       seed = NULL)
                  }

    for(i in seq_len(numIslands))
    { 
      # get summary of GAs evolution
      j <- seq((iter-1)*migrationInterval+1, iter*migrationInterval)
      sumryStat[[i]][j,] <- GAs[[i]]@summary
      # migration step
      from <- i
      to <- (i %% numIslands) + 1
      ## select top individuals to migrationPop
      j <- order(GAs[[from]]@fitness, decreasing = TRUE)[seq(migPop)]
      migrationPop <- GAs[[from]]@population[j,,drop=FALSE]
      ## substitute the worst individuals
      # j <- order(GAs[[to]]@fitness, decreasing = FALSE)[seq(migPop)]
      ## substitute random individuals
      # j <- sample(GAs[[to]]@popSize, size = migPop)
      ## substitute random individuals but the elitist ones
      j <- sample(setdiff(seq(GAs[[to]]@popSize),
                          order(GAs[[to]]@fitness, decreasing = TRUE)[seq(elitism)]),
                  size = migPop)
      newpop <- rbind(GAs[[to]]@population[-j,,drop=FALSE], migrationPop)
      POPs[[to]] <- newpop
    }
    object@islands <- GAs
    object@summary <- sumryStat

    if(is.function(monitor)) 
      { monitor(object) }

    # check stopping criteria
    maxFitnessIslands <- sapply(sumryStat, function(x) 
                                apply(x[seq(iter*migrationInterval),,drop=FALSE],1,max))
    if(all(apply(maxFitnessIslands, 2, garun) > run)) break
    if(all(maxFitnessIslands >= maxFitness)) break
  }
  
  # get islands' fitness values
  fitnessValues <- lapply(object@islands, function(x) x@fitnessValue)
  # get islands' solutions
  solutions <- lapply(object@islands, function(x) x@solution)
  # colnames(solution) <- parNames(GAs[[1]])
  
  # in case of premature convergence remove NA from summary fitness evalutations
  object@summary <- lapply(object@summary, function(x) 
                          { x <- na.exclude(x)
                            attr(x, "na.action") <- NULL
                            x })

  # islands fitness & solution
  object@fitnessValues <- fitnessValues
  object@solutions <- solutions
  # overall fitness & solution
  object@fitnessValue <- max(unlist(fitnessValues), na.rm = TRUE)
  object@solution <- solutions[[which(object@fitnessValue == unlist(fitnessValues))[1]]]

  # return an object of class 'gaisl'
  return(object)
}

setClass(Class = "gaisl", 
         representation(call = "language",
                        type = "character",
                        lower = "numericOrNA", 
                        upper = "numericOrNA", 
                        nBits = "numericOrNA", 
                        names = "character",
                        popSize = "numeric",
                        numIslands = "numeric",
                        migrationRate = "numeric",
                        migrationInterval = "numeric",
                        maxiter = "numeric",
                        run = "numeric", 
                        suggestions = "matrix",
                        elitism = "numeric", 
                        pcrossover = "numeric", 
                        pmutation = "numericOrNA",
                        optim = "logical",
                        islands = "list",
                        summary = "list",
                        fitnessValues = "list",
                        solutions = "list",
                        fitnessValue = "numeric",
                        solution = "matrix"
                      ),
         package = "GA" 
)

setMethod("print", "gaisl", function(x, ...) str(x))

setMethod("show", "gaisl",
function(object)
 {message("An object of class \"gaisl\"\n")
  message("\nCall:\n", deparse(object@call), "\n\n",sep="")
  message("Available slots:\n")
   print(slotNames(object))
}) 

summary.gaisl <- function(object, ...)
{
  obj <- object@islands[[1]]
  nvars <- ncol(obj@population)
  varnames <- parNames(obj)
  iter <- nrow(object@summary[[1]])
  out <- list(type = object@type,
              numIslands = object@numIslands,
              popSizeIslands = obj@popSize,
              migrationRate = object@migrationRate,
              migrationInterval = object@migrationInterval,
              elitism = object@elitism,
              pcrossover = object@pcrossover,
              pmutation = object@pmutation,
              domain = if(object@type == "real-valued") 
                         { domain <- rbind(object@lower, 
                                           object@upper)
                           rownames(domain) <- c("lower", "upper")
                           if(ncol(domain) == nvars) 
                             colnames(domain) <- varnames 
                           domain }              
                       else NULL,
              iter = iter,
              epoch = iter/object@migrationInterval,
              fitnessValues = unlist(object@fitnessValues),
              solutions = do.call(rbind, object@solutions)
  )
  class(out) <- "summary.gaisl"
  return(out)
}

setMethod("summary", "gaisl", summary.gaisl)

print.summary.gaisl <- function(x, digits = getOption("digits"), ...)
{
  dotargs <- list(...)
  if(is.null(dotargs$head)) dotargs$head <- 10
  if(is.null(dotargs$tail)) dotargs$tail <- 2
  if(is.null(dotargs$chead)) dotargs$chead <- 10
  if(is.null(dotargs$ctail)) dotargs$ctail <- 2
  
 message(cli::rule(left = crayon::bold("Islands Genetic Algorithm"),
                width = min(getOption("width"),40)), "\n\n")
  #message("+-----------------------------------+\n")
  #message("|         Genetic Algorithm         |\n")
  #message("|           Islands Model           |\n")
  #message("+-----------------------------------+\n\n")
  
 message("GA settings: \n")
 message(paste("Type                  = ", x$type, "\n"))
 message(paste("Number of islands     = ", x$numIslands, "\n"))
 message(paste("Islands pop. size     = ", x$popSizeIslands, "\n"))
 message(paste("Migration rate        = ", x$migrationRate, "\n"))
 message(paste("Migration interval    = ", x$migrationInterval, "\n"))
 message(paste("Elitism               = ", x$elitism, "\n"))
 message(paste("Crossover probability = ", format(x$pcrossover, digits = digits), "\n"))
 message(paste("Mutation probability  = ", format(x$pmutation, digits = digits), "\n"))
  if(x$type == "real-valued")
    {message(paste("Search domain = \n"))
      do.call(".printShortMatrix", 
              c(list(x$domain, digits = digits), 
                dotargs[c("head", "tail", "chead", "ctail")]))
    }

 message("\nGA results: \n")
 message(paste("Iterations              =", format(x$iter, digits = digits), "\n"))
 message(paste("Epochs                  =", format(x$epoch, digits = digits), "\n"))
 message(paste("Fitness function values = "))
 message(format(x$fitnessValues, digits = digits), "\n")
 message(paste("Solutions = \n"))
  do.call(".printShortMatrix", 
          c(list(x$solution, digits = digits), 
            dotargs[c("head", "tail", "chead", "ctail")]))
  invisible()
}

plot.gaisl <- function(x, ...)
{ 
  args <- list(...)
  sumryStat <- lapply(x@summary, na.omit)
  trace <- sapply(sumryStat, function(x) x[,1])
  colnames(trace) <- paste0("island", seq(ncol(trace)))
  iter <- seq(nrow(trace))
  if(is.null(args$ylim)) args$ylim <- range(trace)
  if(is.null(args$xlim)) args$xlim <- range(iter)
  if(is.null(args$xlab)) args$xlab <- "Generation"
  if(is.null(args$ylab)) args$ylab <- "Fitness values"
  
  col <- if(is.null(args$col))
           { palette <- colorRampPalette(c("#CCEBC5", "#A8DDB5", "#7BCCC4", 
                                           "#4EB3D3", "#2B8CBE", "#0868AC"), 
                                         space = "Lab")
             palette(ncol(trace)) } else args$col
  lty <- if(is.null(args$lty)) 1 else args$lty
  lwd <- if(is.null(args$lwd)) 2 else args$lwd
  
  do.call("plot", c(1, 1, type = "n", args))
  grid(equilogs=FALSE)
  matplot(iter, trace, type = "l", add = TRUE, 
          lty = lty, lwd = lwd, col = col)
  
  out <- data.frame(iter = iter, trace)
  invisible(out)
}

setMethod("plot", "gaisl", plot.gaisl)

