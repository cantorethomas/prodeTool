#' Run PRODE on pre-processed input data.
#'
#' @details For each gene present in the adjacency matrix and the score matrix in \code{prodeInput}
#'    object, PRODE combines gene-level and first neighborhood-level signals. In the case of
#'    NIE scores, PRODE combines percentiles of average scores for each gene across samples (gene-level signal)
#'    and percentiles of RRA p-values for each gene (neighborhood-level signal). RRA p-values
#'    are computed by running the RRA algorithm (Kolde et al. 2012). Briefly, for each gene,
#'    first-level neighbors are retrieved from adjacency matrix and their skewness
#'    towards low gene-level percentiles is quantified. The final NIE score is computes as
#'    \deqn{NIE_{score} = log(u_{gene} \times u_{neigh})} where \eqn{u_{gene}} and \eqn{u_{neigh}} are the
#'    percentiles of gene-level and neighborhood-level signal. NICE scores are computed
#'    following an identical procedure, except for gene-level signal, which is obtained from
#'    the coefficients resulting from linear model fits of each gene, corresponding to the grouping
#'    variable. Compared to NIE scores, NICE scores capture differential signal between two
#'    conditions.
#' @param prodeInput object of class ProdeInput. This is generated by first
#'    running \code{getProdeInput} function.
#' @param scaledEst logical, whether or not consider ranks of scaled coefficients
#'    from linear model fits. If set to \code{FALSE} gene ranks are computed
#'    considering thee unscaled coefficient. Default set to \code{TRUE}.
#' @param computeBack logical, if set to \code{TRUE}, computes background distribution
#'    for each neighborhood size. If set to \code{FALSE}, as default, pre-computed
#'    background distirbution is used (Weibull parameters of fitted distributions).
#' @param filterCtrl logical, whether or not to filter genes depending on
#'     average values of control samples, before running RRA algorithm. If set to
#'     \code{TRUE}, genes that display average values of control samples > 0, will be filtered
#'     out. Ignored in case of NIE scores. Default set to \code{FALSE}.
#' @param n_iter integer, number of random iterations to generate the background
#'     null distribution of random Rhos for the RRA algorithm. This parameter
#'     is ignored if \code{computeBack} is set to \code{FALSE}.
#' @param cores integer, the number of cores, default=1 (no parallelization). This parameter
#'     is ignored if \code{computeBack} is set to \code{FALSE}.
#' @param extendedNICEStats logical, whether to compute extended per-group
#'     stats on score matrix when computing NICE scores. Default set to \code{FALSE}.
#'     Ignored in case of NIE scores. Default set to \code{FALSE}
#' @returns for \code{results()}, it returns a data.frame with different results
#'     as columns, depending if NIE or NICE scores have been computed.
#'     \subsection{Gene-level results}{
#'         \itemize{
#'          \item{\code{Estimate}} in case of NIE scores, it corresponds to the intercept of model fit,
#'          i.e., for each gene, the average values across samples. In case of NICE scores, it's
#'          the coefficient of to the variable encoding the condition of
#'          interest, as represented in the \code{prodeInput} object.,
#'          \item{\code{Std...Error}} is the coefficient standard error, as computed by \code{summary(lm())}
#'          \item{\code{t.value}} is the Estimate rescaled by Std. Error, as computed by \code{summary(lm())}
#'          \item{\code{Pr...t..}} is the probablity associated to the t-value, as computed by \code{summary(lm())}
#'          }
#'      }
#'     \subsection{Neighborhood-level results}{
#'         \itemize{
#'              \item{\code{rra_score}} is the \eqn{\rho} value computed by RRA algorithm for each gene.
#'              \item{\code{rra_p}} is the p-value corresponding to each \eqn{\rho} value (computed according to neighborhood size).
#'              \item{\code{rra_fdr}} is the FDR computed from \code{rra_p}.
#'         }
#'     }
#'     \subsection{Final Score results}{
#'         \itemize{
#'              \item{\code{u_gene}} is the percentile of gene-level signal (\code{Estimate}
#'              or \code{t.value} columns, depeindin if \code{scaledEst=T})
#'              \item{\code{u_neigh}} is the percentile of neighborhood-level signal (\code{rra_p}).
#'              \item{\code{NIE_score}} or \code{NICE_score} computed as \eqn{log(u_{gene} \times u_{neigh})}
#'         }
#'     }
#'      \subsection{If \code{extendedNICEStats=TRUE}}{
#'           \itemize{
#'               \item{\code{ctrl_mean}} is the average value, for each gene, of control samples.
#'               \item{\code{case_mean}} is the average value, for each gene, of case samples.
#'               \item{\code{ctrl_sd}} is the standard deviation of each gene values in control samples.
#'               \item{\code{case_sd}} is the standard deviation of each gene values in case samples.
#'               \item{\code{ctrl_n}} is the number of samples in the control group.
#'               \item{\code{case_n}} is the number of samples in the case group.
#'          }
#'      }
#' @export
runProde <- function(
    prodeInput,
    scaledEst=T,
    computeBack=F,
    n_iter=10000,
    cores=1,
    filterCtrl = F,
    extendedNICEStats=F
){

    message("\n\nRunning PRODE on ", ncol(assay(prodeInput)), " samples.\n")
    message("* Running Linear models fit.")

    if (modality(prodeInput) == 'NIE_score'){
      # It is forced to FALSE in case of NIE scores
      extendedNICEStats <- F
      filterCtrl <- F

    }

    fit_tab <- fitLms( # fast fit linear models to each gene + covariates
      x                 = designMatrix(prodeInput),
      y                 = SummarizedExperiment::assay(prodeInput),
      extendedNICEStats = extendedNICEStats
    )

    rownames(fit_tab) <- rownames(prodeInput)

    message("* Subsetting adjacency matrix.")

    filtered_data <- .filterAdjMatrix(
      filterCtrl = filterCtrl,
      prodeInput = prodeInput,
      fit_tab    = fit_tab
    )

    filtered <- filtered_data[['filtered']]
    fit_tab  <- filtered_data[['fit_tab']]
    adj_m    <- filtered_data[['adjMatrix']]

    stopifnot(.checkBetAdj(fit_tab, adj_m))

    message("\t - Filtered  ", nrow(filtered), " genes")
    message("\t - Remaining ", nrow(fit_tab), " genes")

    if (computeBack){

        message("* Computing background distribution for RRA statistics (this may take a while).")
        if (cores > 1){

            back_dis <- getRandomRhosPar(
                adj_m  = adj_m,
                n_iter = n_iter,
                cores  = cores
            )

        } else {

            back_dis <- getRandomRhos(
                adj_m  = adj_m,
                n_iter = n_iter
            )

        }

        message("* Computing ", unlist(strsplit(modality(prodeInput), '_')), '.')

        rra_tab <- getRealRhos(
            bet_tab  = fit_tab,
            adj_m    = adj_m,
            back_dis = back_dis,
            scaledEst = scaledEst
        )

    } else {

        message("* Computing ", gsub('_', ' ', modality(prodeInput)), '.')

        rra_tab <- getRealRhosFitDistr(
            bet_tab  = fit_tab,
            adj_m    = adj_m,
            back_par = ww,
            scaledEst = scaledEst
        )

    }

    ## 4. Collect final output .................................................

    message("* Done!")

    newProdeResults(
      fit_tab   = fit_tab,
      rra_tab   = rra_tab,
      adjMatrix = adj_m,
      modality  = modality(prodeInput),
      filtered  = filtered
    )

}

