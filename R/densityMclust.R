densityMclust <- function(data, ..., plot = TRUE) 
{
  mc <- match.call()
  obj <- Mclust(data, ...)
  if(is.null(obj)) return(obj)
  obj$call <- mc
  obj$density <- dens(data = obj$data, 
                      modelName = obj$modelName,
                      parameters = obj$parameters, 
                      logarithm = FALSE)
  class(obj) <- c("densityMclust", "Mclust")
  if(plot) plot(obj, what = "density")
  return(obj)
}

predict.densityMclust <- function(object, newdata, 
	                                what = c("dens", "cdens", "z"), 
																	logarithm = FALSE, ...)
{
  if(!inherits(object, "densityMclust")) 
    stop("object not of class 'densityMclust'")
  if(missing(newdata))
    { newdata <- object$data }
  newdata <- as.matrix(newdata)
  if(ncol(object$data) != ncol(newdata))
    { stop("newdata must match ncol of object data") }
  what <- match.arg(what, choices = eval(formals(predict.densityMclust)$what))	
  pro <- object$parameters$pro; pro <- pro/sum(pro)
  noise <- (!is.na(object$hypvol))
  cl <- c(seq(object$G), if(noise) 0)

  switch(what,
         "dens" = 
				 {  
					 out <- dens(data = newdata, 
					             modelName = object$modelName, 
                       parameters = object$parameters,
                       logarithm = logarithm) 
         },
				 "cdens" =
         {
					 z <- cdens(data = newdata, 
					            modelName = object$modelName, 
					            parameters = object$parameters,
					            logarithm = TRUE)
					 z <- if(noise) cbind(z, log(object$parameters$Vinv))
                else      cbind(z) # drop redundant attributes
           colnames(z) <- cl
           out <- if(!logarithm) exp(z) else z
         },
				 "z" = 
				 {
					 z <- cdens(data = newdata, 
					            modelName = object$modelName, 
                      parameters = object$parameters,
                      logarithm = TRUE)
					 z <- if(noise) cbind(z, log(object$parameters$Vinv))
                else      cbind(z) # drop redundant attributes
					 # TODO: to be removed at a certain point
           # z <- sweep(z, MARGIN = 2, FUN = "+", STATS = log(pro))
           # z <- sweep(z, MARGIN = 1, FUN = "-", STATS = apply(z, 1, logsumexp_old))
           # colnames(z) <- cl
           # out <- if(!logarithm) exp(z) else z
           z <- softmax(z, log(pro))
           colnames(z) <- cl
           out <- if(logarithm) log(z) else z
         }
	)
	
  return(out)
}

plot.densityMclust <- function(x, data = NULL, what = c("BIC", "density", "diagnostic"), ...) 
{
  object <- x # Argh.  Really want to use object anyway

  what <- match.arg(what, several.ok = TRUE)
  if(object$d > 1) 
    what <- setdiff(what, "diagnostic")
  oldpar <- par(no.readonly = TRUE)
  # on.exit(par(oldpar))
  
  plot.densityMclust.density <- function(...)
  { 
    if(object$d == 1)      plotDensityMclust1(object, data = data, ...)
    else if(object$d == 2) plotDensityMclust2(object, data = data, ...)
    else                   plotDensityMclustd(object, data = data, ...)
  }
  
  plot.densityMclust.bic <- function(...)
  { 
    plot.mclustBIC(object$BIC, ...)
  }
  
  plot.densityMclust.diagnostic <- function(...)
  { 
    densityMclust.diagnostic(object, ...) 
  }
  
  if(interactive() & length(what) > 1)
    { title <- "Model-based density estimation plots:"
      # present menu waiting user choice
      choice <- menu(what, graphics = FALSE, title = title)
      while(choice != 0)
           { if(what[choice] == "BIC")        plot.densityMclust.bic(...)
             if(what[choice] == "density")    plot.densityMclust.density(...)
             if(what[choice] == "diagnostic") plot.densityMclust.diagnostic(...)
             # re-present menu waiting user choice
             choice <- menu(what, graphics = FALSE, title = title)
           }
  } 
  else 
    { if(any(what == "BIC"))        plot.densityMclust.bic(...)
      if(any(what == "density"))    plot.densityMclust.density(...)
      if(any(what == "diagnostic")) plot.densityMclust.diagnostic(...)
  }
 
  invisible()
}


plotDensityMclust1 <- function(x, data = NULL, col = gray(0.3), hist.col = "lightgrey", hist.border = "white", breaks = "Sturges", ...) 
{
  object <- x # Argh.  Really want to use object anyway
  mc <- match.call(expand.dots = TRUE)
  mc$x <- mc$data <- mc$col <- mc$hist.col <- mc$hist.border <- mc$breaks <- NULL
  xlab <- mc$xlab
  if(is.null(xlab)) 
    xlab <- deparse(object$call$data)
  ylab <- mc$ylab
  if(is.null(ylab)) 
    ylab <- "Density"
  #
  xrange <- extendrange(object$data, f = 0.1)
  xlim <- eval(mc$xlim, parent.frame())
  if(!is.null(xlim)) 
    xrange <- range(xlim)
  ylim <- eval(mc$ylim, parent.frame())
  #
  eval.points <- seq(from = xrange[1], to = xrange[2], length = 1000)
  d <- predict.densityMclust(object, eval.points)
  #
  if(!is.null(data)) 
  { 
    h <- hist(data, breaks = breaks, plot = FALSE)
    plot(h, freq = FALSE, col = hist.col, border = hist.border, main = "",
         xlim = range(h$breaks, xrange), 
         ylim =  if(!is.null(ylim)) range(ylim) else range(0, h$density, d),
         xlab = xlab, ylab = ylab)
    box()
    mc[[1]] <- as.name("lines")
    mc$x <- eval.points
    mc$y <- d
    mc$type <- "l"
    mc$col <- col
    eval(mc, parent.frame())
  } else
  { 
    mc[[1]] <- as.name("plot")
    mc$x <- eval.points
    mc$y <- d
    mc$type <- "l"
    mc$col <- col
    mc$xlim <- xlim
    mc$ylim <- if(!is.null(ylim)) range(ylim) else range(0, d)
    mc$ylab <- ylab
    mc$xlab <- xlab
    eval(mc, parent.frame())
  }
  invisible()
}

plotDensityMclust2 <- function(x, data = NULL, 
                               nlevels = 11, levels = NULL, 
                               prob = c(0.25, 0.5, 0.75),
                               points.pch = 1, points.col = 1, 
                               points.cex = 0.8, 
                               ...) 
{
  # This function call surfacePlot() with a suitable modification of arguments
  object <- x # Argh.  Really want to use object anyway
  mc <- match.call(expand.dots = TRUE)
  mc$x <- mc$points.pch <- mc$points.col <- mc$points.cex <- NULL

  mc$nlevels <- nlevels
  mc$levels <- levels
  if(!is.null(mc$type))
    if(mc$type == "level") mc$type <- "hdr" # TODO: to be removed at certain point
  if(isTRUE(mc$type == "hdr"))
    { mc$levels <- c(sort(hdrlevels(object$density, prob)), 
                     1.1*max(object$density))
      mc$nlevels <- length(mc$levels)
    }
  
  if(is.null(data)) 
    { addPoints <- FALSE
      mc$data <- object$data } 
  else
    { data <- as.matrix(data)
      stopifnot(ncol(data) == ncol(object$data))
      addPoints <- TRUE }
  
  # set mixture parameters
  par <- object$parameters
  # these parameters should be missing 
  par$variance$cholSigma <- par$Sigma <- NULL
  if(is.null(par$pro)) par$pro <- 1
  par$variance$cholsigma <- par$variance$sigma
  for(k in seq(par$variance$G))
     { par$variance$cholsigma[,,k] <- chol(par$variance$sigma[,,k]) }
  mc$parameters <- par
  # now surfacePlot() is called
  mc[[1]] <- as.name("surfacePlot")
  out <- eval(mc, parent.frame())
  if(addPoints)
    points(data, pch = points.pch, col = points.col, cex = points.cex)
  #
  invisible(out)
}

plotDensityMclustd <- function(x, data = NULL, 
                               nlevels = 11, levels = NULL, 
                               prob = c(0.25, 0.5, 0.75),
                               points.pch = 1, 
                               points.col = 1, 
                               points.cex = 0.8, 
                               gap = 0.2, ...) 
{
  # This function call surfacePlot() with a suitable modification of arguments
  
  object <- x # Argh.  Really want to use object anyway
  mc <- match.call(expand.dots = TRUE)
  mc$x <- mc$points.pch <- mc$points.col <- mc$points.cex <- mc$gap <- NULL

  mc$nlevels <- nlevels
  mc$levels <- levels
  mc$prob <- prob
  if(!is.null(mc$type))
    if(mc$type == "level") mc$type <- "hdr" # TODO: to be removed at certain point

  if(is.null(data)) 
    { data <- mc$data <- object$data
      addPoints <- FALSE }
  else
    { data <- as.matrix(data)
      stopifnot(ncol(data) == ncol(object$data))
      addPoints <- TRUE  }
  
  
  nc <- object$d
  oldpar <- par(mfrow = c(nc, nc), 
                mar = rep(gap/2,4), 
                oma = rep(3, 4),
                no.readonly = TRUE)
  on.exit(par(oldpar))

  for(i in seq(nc))
     { for(j in seq(nc)) 
          { if(i == j) 
              { 
                plot(data[,c(i,j)], type="n",
                     xlab = "", ylab = "", axes=FALSE)
                text(mean(par("usr")[1:2]), mean(par("usr")[3:4]), 
                     colnames(data)[i], cex = 1.5, adj = 0.5)
                box()
            } 
            else 
              { # set mixture parameters
                par <- object$parameters
                if(is.null(par$pro)) par$pro <- 1
                par$mean <- par$mean[c(j,i),,drop=FALSE]
                par$variance$d <- 2
                sigma <- array(dim = c(2, 2, par$variance$G))
                for(g in seq(par$variance$G))
                  sigma[,,g] <- par$variance$sigma[c(j,i),c(j,i),g]
                par$variance$sigma <- sigma
                par$variance$Sigma <- NULL
                par$variance$cholSigma <- NULL
                par$variance$cholsigma <- NULL
                mc$parameters <- par
                mc$data <- object$data[,c(j,i)]
                mc$axes <- FALSE
                mc[[1]] <- as.name("surfacePlot")
                eval(mc, parent.frame())
                box()
                if(addPoints & (j > i))
                  points(data[,c(j,i)], pch = points.pch, 
                         col = points.col, cex = points.cex)
              }
              if(i == 1 && (!(j%%2))) axis(3)
              if(i == nc && (j%%2))   axis(1)
              if(j == 1 && (!(i%%2))) axis(2)
              if(j == nc && (i%%2))   axis(4)
          }
  }
  #
  invisible()
}

dens <- function(data, modelName, parameters, logarithm = FALSE, warn = NULL, ...)
{
  if(is.null(warn)) warn <- mclust.options("warn")
  # aux <- list(...)
  logcden <- cdens(data = data,
                   modelName = modelName,
                   parameters = parameters,
                   logarithm = TRUE, 
                   warn = warn)
  if(attr(logcden, "returnCode") < 0)
    stop(attr(logcden, "WARNING"))
  pro <- parameters$pro
  if(is.null(pro))
    stop("mixing proportions must be supplied")
  noise <- (!is.null(parameters$Vinv))
  if(noise) 
  {
    proNoise <- pro[length(pro)]
    pro <- pro[-length(pro)]
  }
  if(any(proz <- pro == 0)) 
  { 
    pro <- pro[!proz]
    logcden <- logcden[, !proz, drop = FALSE]
  }
  # TODO: to be removed at a certain point
  # logcden <- sweep(logcden, 2, FUN = "+", STATS = log(pro))
  # maxlog <- apply(logcden, 1, max)
  # logcden <- sweep(logcden, 1, FUN = "-", STATS = maxlog)
  # logden <- log(apply(exp(logcden), 1, sum)) + maxlog
  logden <- logsumexp(logcden, log(pro))
  #
  if(noise) 
    logden <- log(exp(logden) + proNoise*parameters$Vinv)
  out <- if(logarithm) logden else exp(logden)
  return(out)
}

cdens <- function(data, modelName, parameters, logarithm = FALSE, warn = NULL, ...)
{
  modelName <- switch(EXPR = modelName,
                      X = "E",
                      XII = "EII",
                      XXI = "EEI",
                      XXX = "EEE",
                      modelName)
  checkModelName(modelName)
  funcName <- paste("cdens", modelName, sep = "")
  mc <- match.call(expand.dots = TRUE)
  mc[[1]] <- as.name(funcName)
  mc$modelName <- NULL
  eval(mc, parent.frame())
}

densityMclust.diagnostic <- function(object, type = c("cdf", "qq"), 
                                     col = c("black", "black"), 
                                     lwd = c(2,1), lty = c(1,1),
                                     legend = TRUE, grid = TRUE, 
                                     ...)
{
# Diagnostic plots for density estimation 
# (only available for the one-dimensional case)
# 
# Arguments:
# object = a 'densityMclust' object
# type = type of diagnostic plot:
#   "cdf" = fitted CDF  vs empirical CDF
#   "qq"  = fitted CDF evaluated over the observed data points vs 
#           the quantile from a uniform distribution
#
# Reference: 
# Loader C. (1999), Local Regression and Likelihood. New York, Springer, 
#   pp. 87-90)

  stopifnot("first argument must be an object of class 'densityMclust'" = 
	          inherits(object, "densityMclust"))
  if(object$d > 1)
    { warning("only available for one-dimensional data") 
      return() }  
  type <- match.arg(type, c("cdf", "qq"), several.ok = TRUE)
  # main <- if(is.null(main) || is.character(main)) FALSE else as.logical(main)

  data <- as.numeric(object$data)
  n <- length(data)
  cdf <- cdfMclust(object, data = data, ngrid = min(n*10,1000), ...)
  
  oldpar <- par(no.readonly = TRUE)
  if(interactive() & length(type) > 1) 
    { par(ask = TRUE)
      on.exit(par(oldpar)) }
  
  if(any(type == "cdf"))
  { # Fitted CDF vs Emprical CDF    
    empcdf <- ecdf(data)
    plot(empcdf, do.points = FALSE, verticals = TRUE,
         col = col[2], lwd = lwd[2], lty = lty[2],
         xlab = deparse(object$call$data), 
         ylab = "Cumulative Distribution Function",
         panel.first = if(grid) grid(equilogs=FALSE) else NULL,
         main = NULL, ...)
    # if(main) title(main = "CDF plot", cex.main = 1.1)
    lines(cdf, col = col[1], lwd = lwd[1], lty = lty[1])
    rug(data)
    if(legend)
      { legend("bottomright", legend = c("Estimated CDF", "Empirical CDF"), 
               ncol = 1, inset = 0.05, cex = 0.8,
               col = col, lwd = lwd, lty = lty) }
  }
  
  if(any(type == "qq"))
  { # Q-Q plot
    q <- quantileMclust(object, p = ppoints(n))
    plot(q, sort(data),
         xlab = "Quantiles from estimated density", 
         ylab = "Sample Quantiles", 
         panel.first = if(grid) grid(equilogs=FALSE) else NULL,
         main = NULL, ...)
		# add qq-line
		Q.y <- quantile(sort(data), probs = c(.25,.75))
		Q.x <- quantileMclust(object, p = c(.25,.75))
		b <- (Q.y[2] - Q.y[1])/(Q.x[2] - Q.x[1])
		a <- Q.y[1] - b*Q.x[1]
		abline(a, b, untf = TRUE, col = 1, lty = 2)
    # old method to draw qq-line
    # with(list(y = sort(data), x = q),
    #      { i <- (y > quantile(y, 0.25) & y < quantile(y, 0.75))
    #        abline(lm(y ~ x, subset = i), lty = 2) 
    #      })
    # P-P plot
    # cdf <- cdfMclust(object, data, ...)
    # plot(seq(1,n)/(n+1), cdf$y, xlab = "Uniform quantiles", 
    #      ylab = "Cumulative Distribution Function",
		#      panel.first = if(grid) grid(equilogs=FALSE) else NULL)
    # abline(0, 1, untf = TRUE, col = col[2], lty = lty[1])
  }

  invisible()
} 

cdfMclust <- function(object, data, ngrid = 100, ...)
{
# Cumulative Density Function
# (only available for the one-dimensional case)
#
# Returns the estimated CDF evaluated at points given by the optional
# argument data. If not provided, a regular grid of ngrid points is used. 
#
# Arguments:
# object = a 'densityMclust' object
# data = the data vector
# ngrid = the length of rectangular grid 
  
  stopifnot("first argument must be an object of class 'densityMclust'" = 
            inherits(object, "densityMclust"))
  
  if(missing(data))
    { eval.points <- extendrange(object$data, f = 0.1)
      eval.points <- seq(eval.points[1], eval.points[2], length.out = ngrid) }
  else
    { eval.points <- sort(as.vector(data))
      ngrid <- length(eval.points) }
  
  G <- object$G
  pro <- object$parameters$pro
  mean <- object$parameters$mean
  var <- object$parameters$variance$sigmasq
  if(length(var) < G) var <- rep(var, G)
  noise <- (!is.null(object$parameters$Vinv))

  cdf <- rep(0, ngrid)
  for(k in seq(G))
     { cdf <- cdf + pro[k]*pnorm(eval.points, mean[k], sqrt(var[k])) }
  if(noise) 
    cdf <- cdf/sum(pro[seq(G)])
  
  out <- list(x = eval.points, y = cdf)    
  return(out)
}

quantileMclust <- function(object, p, ...)
{
# Calculate the quantile of a univariate mixture corresponding to cdf
# equal to p using bisection line search method.
#
# Arguments:
# object = a 'densityMclust' object
# p = vector of probabilities (0 <= p <= 1)

  stopifnot(inherits(object, "densityMclust"))
  if(object$d != 1)
    { stop("quantile function only available for 1-dimensional data") }
  p <- as.vector(p)
  m <- object$parameters$mean
  s <- sqrt(object$parameters$variance$sigmasq)
  if(object$modelName == "E") s <- rep(s, object$G)
  r <- matrix(as.double(NA), nrow = length(p), ncol = object$G)
  for(g in 1:object$G)
  {
    r[,g] <- qnorm(p, mean = m[g], sd = s[g])
  }
  if(object$G == 1) return(as.vector(r))
  q <- rep(as.double(NA), length(p))
  for(i in 1:length(p))
  {
    F <- function(x) cdfMclust(object, x)$y - p[i]
    q[i] <- uniroot(F, interval = range(r[i,]), tol = sqrt(.Machine$double.eps))$root
  }
  q[ p < 0 | p > 1] <- NaN
  q[ p == 0 ] <- -Inf
  q[ p == 1 ] <- Inf
  return(q)  
}
