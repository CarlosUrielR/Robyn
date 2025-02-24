# Copyright (c) Meta Platforms, Inc. and its affiliates.

# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Includes function mic_men, adstock_geometric, adstock_weibull,
# saturation_hill, plot_adstock, plot_saturation

####################################################################
#' Michaelis-Menten transformation
#'
#' The Michaelis-Menten function is used to fit the spend exposure relationship
#' for paid media variables, when exposure metrics like impressions, clicks or
#' GRPs are provided in \code{paid_media_vars} instead of spend metric.
#'
#' @param x Numeric value or vector. Input media spend when
#' \code{reverse = FALSE}. Input media exposure metrics (impression, clicks,
#' GRPs, etc.) when \code{reverse = TRUE}.
#' @param Vmax A numeric value. Indicates maximum rate achieved by the system.
#' @param Km A numeric value. The Michaelis constant.
#' @param reverse A logical value. Input media spend when \code{reverse = FALSE}.
#' Input media exposure metrics (impression, clicks, GRPs etc.) when \code{reverse = TRUE}.
#' @export
mic_men <- function(x, Vmax, Km, reverse = FALSE) {
  if (!reverse) {
    mm_out <- exposure <- Vmax * x / (Km + x)
  } else {
    mm_out <- spend <- x * Km / (Vmax - x)
  }
  return(mm_out)
}


####################################################################
#' Geometric adstocking function
#'
#' The geometric adstock function is the classic one-parametric adstock function.
#'
#' @param x A numeric vector.
#' @param theta A numeric value. Theta is the only parameter and means fixed decay
#' rate. Assuming TV spend on day 1 is 100€ and theta = 0.7, then day 2 has
#' 100 x 0.7 = 70€ worth of effect carried-over from day 1, day 3 has 70 x 0.7 = 49€
#' from day 2 etc. Rule-of-thumb for common media genre: TV c(0.3, 0.8), OOH/Print/
#' Radio c(0.1, 0.4), digital c(0, 0.3).
#' @export
adstock_geometric <- function(x, theta) {
  x_decayed <- c(x[1], rep(0, length(x) - 1))
  for (xi in 2:length(x_decayed)) {
    x_decayed[xi] <- x[xi] + theta * x_decayed[xi - 1]
  }

  thetaVecCum <- theta
  for (t in 2:length(x)) {
    thetaVecCum[t] <- thetaVecCum[t - 1] * theta
  } # plot(thetaVecCum)

  return(list(x_decayed = x_decayed, thetaVecCum = thetaVecCum))
}

####################################################################
#' Weibull adstock functions
#'
#' The Weibull adstock is a two-parametric adstock function that allows changing
#' decay rate over time, as opposed to the fixed decay rate over time as in
#' Geometric adstock. It has two options, the cumulative density function "cdf"
#' or the probability density function "pdf".
#'
#' @param x A numeric vector.
#' @param shape,scale Numeric. The CDF (Cumulative Distribution Function) of Weibull has
#' two parameters, shape & scale, and has flexible decay rate, compared to Geometric
#' adstock with fixed decay rate. The shape parameter controls the shape of the decay
#' curve. Recommended bound is c(0.0001, 2). The larger the shape, the more S-shape. The
#' smaller, the more L-shape. Scale controls the inflexion point of the decay curve. We
#' recommend very conservative bounce of c(0, 0.1), because scale increases the adstock
#' half-life greatly.
#' The PDF (Probability Density Function) of the Weibull also shape & scale as parameter
#' and also has flexible decay rate as Weibull CDF. The difference is that Weibull PDF
#' offers lagged effect. When shape > 2, the curve peaks after x = 0 and has NULL slope at
#' x = 0, enabling lagged effect and sharper increase and decrease of adstock, while the
#' scale parameter indicates the limit of the relative position of the peak at x axis; when
#' 1 < shape < 2, the curve peaks after x = 0 and has infinite positive slope at x = 0,
#' enabling lagged effect and slower increase and decrease of adstock, while scale has the
#' same effect as above; when shape = 1, the curve peaks at x = 0 and reduces to exponential
#' decay, while scale controls the inflexion point; when 0 < shape < 1, the curve peaks at
#' x = 0 and has increasing decay, while scale controls the inflexion point. When all
#' possible shapes are relevant, we recommend c(0.0001, 10) as bounds for shape; when only
#' strong lagged effect is of interest, we recommend c(2.0001, 10) as bound for shape. In
#' all cases, we recommend conservative bound of c(0, 0.1) for scale. Due to the great
#' flexibility of Weibull PDF, meaning more freedom in hyperparameter spaces for Nevergrad
#' to explore, it also requires larger iterations to converge.
#' @param windlen An integer value. Length of modelling window.
#' @param type Character. Accepts "cdf" or "pdf". CDF, or cumulative density
#' function of the Weibull function allows changing decay rate over time in both
#' C and S shape, while the peak value will always stay at the first period,
#' meaning no lagged effect. PDF, or the probability density function, enables
#' peak value occuring after the first period when shape >=1, allowing lagged
#' effect. Run \code{plot_adstock()} to see the difference visually.
#' @export
adstock_weibull <- function(x, shape, scale, windlen=NULL, type) {
  x.n <- length(x)
  x_bin <- 1:x.n
  if (is.null(windlen)) {windlen <- x.n}
  scaleTrans <- round(quantile(1:windlen, scale), 0)

  if (shape==0) {
    thetaVecCum <- thetaVec <- rep(0, x.n)
  } else {
    if (type == "cdf") {
      thetaVec <- c(1, 1 - pweibull(head(x_bin, -1), shape = shape, scale = scaleTrans)) # plot(thetaVec)
      thetaVecCum <- cumprod(thetaVec) # plot(thetaVecCum)
    } else if (type == "pdf") {
      normalize <- function(x) {
        if (diff(range(x))==0) {
          return(c(1, rep(0, length(x)-1)))
        } else {
          return((x - min(x)) / (max(x) - min(x)))
        }
      }
      thetaVecCum <- normalize(dweibull(x_bin, shape = shape, scale = scaleTrans)) # plot(thetaVecCum)
    }
  }

  x_decayed <- mapply(function(x_val, x_pos) {
    x.vec <- c(rep(0, x_pos - 1), rep(x_val, x.n - x_pos + 1))
    thetaVecCumLag <- shift(thetaVecCum, x_pos - 1, fill = 0)
    x.prod <- x.vec * thetaVecCumLag
    return(x.prod)
  }, x_val = x, x_pos = x_bin)
  x_decayed <- rowSums(x_decayed)

  return(list(x_decayed = x_decayed, thetaVecCum = thetaVecCum))
}

####################################################################
#' Hill saturation function
#'
#' The Hill function applied here is a two-parametric version of the
#' function that allows the saturation curve to flip between S and C shape.
#'
#' @param x A numeric vector.
#' @param alpha A numeric value. Alpha controls the shape of the saturation curve.
#' The larger the alpha, the more S-shape. The smaller, the more C-shape.
#' @param gamma A numeric value. Gamma controls the inflexion point of the
#' saturation curve. The larger the gamma, the later the inflexion point occurs.
#' @param x_marginal A numeric value. When provided, the function returns the
#' Hill-transformed value of the x_marginal input.
#' @export
saturation_hill <- function(x, alpha, gamma, x_marginal = NULL) {
  gammaTrans <- round(quantile(seq(range(x)[1], range(x)[2], length.out = 100), gamma), 4)

  if (is.null(x_marginal)) {
    x_scurve <- x**alpha / (x**alpha + gammaTrans**alpha) # plot(x_scurve) summary(x_scurve)
  } else {
    x_scurve <- x_marginal**alpha / (x_marginal**alpha + gammaTrans**alpha)
  }
  return(x_scurve)
}


####################################################################
#' Adstocking help plot
#'
#' Produce example plots for both Geometric and Weibull adstock.
#'
#' @param plot Boolean. Do you wish to return the plot?
#' @examples
#' plot_adstock()
#' @export
plot_adstock <- function(plot = TRUE) {
  if (plot) {
    ## plot geometric
    geomCollect <- list()
    thetaVec <- c(0.01, 0.05, 0.1, 0.2, 0.5, 0.6, 0.7, 0.8, 0.9)

    for (v in 1:length(thetaVec)) {
      thetaVecCum <- 1
      for (t in 2:100) {
        thetaVecCum[t] <- thetaVecCum[t - 1] * thetaVec[v]
      }
      dt_geom <- data.table(
        x = 1:100,
        decay_accumulated = thetaVecCum,
        theta = thetaVec[v]
      )
      dt_geom[, halflife := which.min(abs(decay_accumulated - 0.5))]
      geomCollect[[v]] <- dt_geom
    }
    geomCollect <- rbindlist(geomCollect)
    geomCollect[, theta_halflife := paste(theta, halflife, sep = "_")]

    p1 <- ggplot(geomCollect, aes(x = x, y = decay_accumulated)) +
      geom_line(aes(color = theta_halflife)) +
      geom_hline(yintercept = 0.5, linetype = "dashed", color = "gray") +
      geom_text(aes(x = max(x), y = 0.5, vjust = -0.5, hjust = 1, label = "Halflife"), colour = "gray") +
      labs(
        title = "Geometric adstock (fixed decay rate)",
        subtitle = "Halflife = time until effect reduces to 50%",
        x = "time unit",
        y = "Media decay accumulated"
      )

    ## plot weibull
    weibullCollect <- list()
    shapeVec <- c(0.5, 1, 2, 9)
    scaleVec <- c(0.01, 0.05, 0.1, 0.15, 0.2, 0.5)
    types <- c("CDF", "PDF")
    n <- 1
    for (t in seq_along(types)) {
      for (v1 in seq_along(shapeVec)) {
        for (v2 in seq_along(scaleVec)) {
          dt_weibull <- data.table(
            x = 1:100,
            decay_accumulated = adstock_weibull(1:100, shape = shapeVec[v1], scale = scaleVec[v2], type = tolower(types[t]))$thetaVecCum,
            shape = paste0("shape=",shapeVec[v1]),
            scale = as.factor(scaleVec[v2]),
            type = types[t]
          )
          dt_weibull[, halflife := which.min(abs(decay_accumulated - 0.5))]
          weibullCollect[[n]] <- dt_weibull
          n <- n+1
        }
      }
    }

    weibullCollect <- rbindlist(weibullCollect)
    #weibullCollect[, scale_halflife := paste(scale, halflife, sep = "_")]
    p2 <- ggplot(weibullCollect, aes(x = x, y = decay_accumulated)) +
      geom_line(aes(color = scale)) +
      facet_grid(shape~type) +
      geom_hline(yintercept = 0.5, linetype = "dashed", color = "gray") +
      geom_text(aes(x = max(x), y = 0.5, vjust = -0.5, hjust = 1, label = "Halflife"), colour = "gray") +
      labs(title = "Weibull adstock CDF vs PDF (flexible decay rate)",
           subtitle = "Halflife = time until effect reduces to 50%",
           x = "time unit",
           y = "Media decay accumulated")

    return(wrap_plots(A = p1, B = p2, design = "ABB"))
  }
}


####################################################################
#' Saturation help plot
#'
#' Produce example plots for the Hill saturation curve.
#'
#' @inheritParams plot_adstock
#' @examples
#' plot_saturation()
#' @export
plot_saturation <- function(plot = TRUE) {
  if (plot) {
    xSample <- 1:100
    alphaSamp <- c(0.1, 0.5, 1, 2, 3)
    gammaSamp <- c(0.1, 0.3, 0.5, 0.7, 0.9)

    ## plot alphas
    hillAlphaCollect <- list()
    for (i in 1:length(alphaSamp)) {
      hillAlphaCollect[[i]] <- data.table(
        x = xSample,
        y = xSample**alphaSamp[i] / (xSample**alphaSamp[i] + (0.5 * 100)**alphaSamp[i]),
        alpha = alphaSamp[i]
      )
    }
    hillAlphaCollect <- rbindlist(hillAlphaCollect)
    hillAlphaCollect[, alpha := as.factor(alpha)]
    p1 <- ggplot(hillAlphaCollect, aes(x = x, y = y, color = alpha)) +
      geom_line() +
      labs(
        title = "Cost response with hill function",
        subtitle = "Alpha changes while gamma = 0.5"
      )

    ## plot gammas
    hillGammaCollect <- list()
    for (i in 1:length(gammaSamp)) {
      hillGammaCollect[[i]] <- data.table(
        x = xSample,
        y = xSample**2 / (xSample**2 + (gammaSamp[i] * 100)**2),
        gamma = gammaSamp[i]
      )
    }
    hillGammaCollect <- rbindlist(hillGammaCollect)
    hillGammaCollect[, gamma := as.factor(gamma)]
    p2 <- ggplot(hillGammaCollect, aes(x = x, y = y, color = gamma)) +
      geom_line() +
      labs(
        title = "Cost response with hill function",
        subtitle = "Gamma changes while alpha = 2"
      )

    return(p1 + p2)
  }
}
