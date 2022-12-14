% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/linear_models_fit_functions.R
\name{fitLms}
\alias{fitLms}
\title{Fit linear models on input data}
\usage{
fitLms(x, y, extendedStats = F)
}
\arguments{
\item{x}{a model.matrix object containing variables included in the linear model.
This object is expected to have rows corresponding to the score-matrix columns.}

\item{y}{a score-matrix with a number of columns equal to x.}

\item{extendedStats}{a logical if extended stats need to be computed.}
}
\value{
a matrix object with results of linear model fitting procedure.
}
\description{
Fit linear models on input data
}
