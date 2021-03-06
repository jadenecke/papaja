#' Format statistics model comparisons (APA 6th edition)
#'
#' This function is the workhorse of the \code{apa_print.anova} for model comparisons. It takes a \code{data.frame}
#' of class \code{apa_model_comp} and produces strings to report the results in accordance with APA manuscript
#' guidelines. \emph{This function is not exported.}
#'
#' @param x Data.frame. A \code{data.frame} of class \code{apa_variance_table} as returned by \code{\link{arrange_anova}}.
#' @param in_paren Logical. Indicates if the formated string will be reported inside parentheses. See details.
#' @param models List. List containing fitted \code{lm}- objects that were compared using \code{anova()}. If the list is named, element names are used as model names in the output object.
#' @param ci Numeric. Confidence level for the confidence interval for \eqn{\Delta R^2} if \code{x} is a model comparison object of class \code{anova}. If \code{ci = NULL} no confidence intervals are estimated.
#' @param observed_predictors Logical. Indicates whether predictor variables were observed. See details.
#' @param boot_samples Numeric. Number of bootstrap samples to estimate confidence intervals for \eqn{\Delta R^2} if \code{x} is a model comparison object of class \code{anova}; ignored if \code{ci = NULL}.
#' @return
#'    A named list containing the following components:
#'
#'    \describe{
#'      \item{\code{statistic}}{A named list of character strings giving the test statistic, parameters, and \emph{p}
#'          value for each factor.}
#'      \item{\code{estimate}}{A named list of character strings giving the effect size estimates for each factor.} % , either in units of the analyzed scale or as standardized effect size.
#'      \item{\code{full_result}}{A named list of character strings comprised of \code{estimate} and \code{statistic} for each factor.}
#'      \item{\code{table}}{A data.frame containing the complete ANOVA table, which can be passed to \code{\link{apa_table}}.}
#'    }
#'
#' @keywords internal
#' @seealso \code{\link{arrange_anova}}, \code{\link{apa_print.aov}}
#' @examples
#'  \dontrun{
#'    mod1 <- lm(Sepal.Length ~ Sepal.Width, data = iris)
#'    mod2 <- update(mod1, formula = . ~ . + Petal.Length)
#'    mod3 <- update(mod2, formula = . ~ . + Petal.Width)
#'
#'    # No bootstrapped Delta R^2 CI
#'    print_model_comp(list(Baseline = mod1, Length = mod2, Both = mod3), boot_samples = 0)
#'  }


print_model_comp <- function(
  x
  , models = NULL
  , ci = NULL
  , boot_samples = 1000
  , in_paren = FALSE
  , observed_predictors = TRUE
) {
  validate(x, check_class = "data.frame")
  validate(x, check_class = "apa_model_comp")
  validate(in_paren, check_class = "logical", check_length = 1)
  validate(ci, check_class = "numeric", check_length = 1, check_range = c(0, 1))
  if(!is.null(models)) validate(models, check_class = "list", check_length = nrow(x) + 1)

  if(!is.null(names(models))) {
    rownames(x) <- names(models)[-1]
  } else rownames(x) <- sanitize_terms(x$term)

  # Concatenate character strings and return as named list
  apa_res <- apa_print_container()

  ## est
  if(boot_samples <= 0) { # No CI
    model_summaries <- lapply(models, summary)
    r2s <- sapply(model_summaries, function(x) x$r.squared)
    delta_r2s <- diff(r2s)

    apa_res$estimate <- sapply(
      seq_along(delta_r2s)
      , function(y) {
        delta_r2_res <- printnum(delta_r2s[y], gt1 = FALSE, zero = FALSE)
        paste0("$\\Delta R^2 ", add_equals(delta_r2_res), "$")
      }
    )
  } else { # Bootstrap CI
    boot_r2_ci <- delta_r2_ci(x, models, ci = ci, R = boot_samples)

    model_summaries <- lapply(models, summary)
    r2s <- sapply(model_summaries, function(x) x$r.squared)
    delta_r2s <- diff(r2s)
    delta_r2_res <- printnum(delta_r2s, gt1 = FALSE, zero = FALSE)

    apa_res$estimate <- paste0(
      "$\\Delta R^2 ", add_equals(delta_r2_res), "$, ", ci * 100, "\\% CI "
      , apply(boot_r2_ci, 1, print_confint, gt1 = FALSE)
    )
  }

  ## stat
  ### Rounding and filling with zeros
  x$statistic <- printnum(x$statistic)
  x$df <- print_df(x$df)
  x$df_res <- print_df(x$df_res)
  x$p.value <- printp(x$p.value, add_equals = TRUE)

  apa_res$statistic <- paste0("$F(", x[["df"]], ", ", x[["df_res"]], ") = ", x[["statistic"]], "$, $p ", x[["p.value"]], "$")
  if(in_paren) apa_res$statistic <- in_paren(apa_res$statistic)
  names(apa_res$statistic) <- x$term

  ## full
  apa_res$full_result <- paste(apa_res$estimate, apa_res$statistic, sep = ", ")
  names(apa_res$estimate) <- names(apa_res$statistic)
  names(apa_res$full_result) <- names(apa_res$statistic)


  # Assemble table
  model_summaries <- lapply(models, function(x) { # Merge b and 95% CI
      lm_table <- apa_print(x, ci = ci + (1 - ci) / 2)$table[, c(1:3)]
      lm_table[, 2] <- apply(cbind(paste0("$", lm_table[, 2], "$"), lm_table[, 3]), 1, paste, collapse = " ")
      lm_table[, -3]
    }
  )

  ## Merge coefficient tables
  coef_table <- Reduce(function(...) merge(..., by = "predictor", all = TRUE), model_summaries)
  rownames(coef_table) <- coef_table$predictor
  coef_table <- coef_table[, colnames(coef_table) != "predictor"]
  coef_table <- coef_table[names(sort(apply(coef_table, 1, function(x) sum(is.na(x))))), ] # Sort predictors to create steps in table
  coef_table <- coef_table[c("Intercept", rownames(coef_table)[rownames(coef_table) != "Intercept"]), ] # Make Intercept first Predictor
  coef_table[is.na(coef_table)] <- ""
  colnames(coef_table) <- names(models)

  ## Add model fits
  model_fits <- lapply(models, broom::glance)
  model_fits <- do.call(rbind, model_fits)
  model_fits <- model_fits[, c("r.squared", "statistic", "df", "df.residual", "p.value", "AIC", "BIC")]

  diff_vars <- c("r.squared", "AIC", "BIC")
  model_diffs <- apply(model_fits[, diff_vars], 2, diff)
  if(length(models) == 2) {
    model_diffs <- matrix(
      model_diffs
      , ncol = length(diff_vars)
      , byrow = TRUE
      , dimnames = list(NULL, diff_vars)
    )
  }
  model_diffs <- as.data.frame(model_diffs, stringsAsFactors = FALSE)

  model_fits <- printnum(
    model_fits
    , margin = 2
    , gt1 = c(FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE)
    , zero = c(FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE)
    , digits = c(2, 2, 0, 0, 3, 2, 2)
  )

  model_fits$r.squared <- sapply(models, function(x) { # Get R^2 with CI
    r2 <- apa_print(x, ci = ci + (1 - ci) / 2, observed_predictors = observed_predictors)$estimate$modelfit$r2 # Calculate correct CI for function focusing on b CI
    r2 <- gsub("R\\^2 = ", "", r2)
    r2 <- gsub(", \\d\\d\\\\\\% CI", "", r2)
    r2
  })

  colnames(model_fits) <- c(paste0("$R^2$ [", ci * 100, "\\% CI]"), "$F$", "$df_1$", "$df_2$", "$p$", "$\\mathrm{AIC}$", "$\\mathrm{BIC}$")

  ## Add differences in model fits
  model_diffs <- printnum(
    model_diffs
    , margin = 2
    , gt1 = c(FALSE, TRUE, TRUE)
    , zero = c(FALSE, TRUE, TRUE)
  )
  model_diffs[, "r.squared"] <- gsub(", \\d\\d\\\\\\% CI", "", gsub("\\\\Delta R\\^2 = ", "", unlist(apa_res$estimate))) # Replace by previous estimate with CI
  model_diffs <- rbind("", model_diffs)

  r2_diff_colname <- if(boot_samples <= 0) "$\\Delta R^2$" else paste0("$\\Delta R^2$ [", ci * 100, "\\% CI]")
  colnames(model_diffs) <- c(r2_diff_colname, "$\\Delta \\mathrm{AIC}$", "$\\Delta \\mathrm{BIC}$")

  diff_stats <- x[, c("statistic", "df", "df_res", "p.value")]
  diff_stats$p.value <- gsub("= ", "", diff_stats$p.value) # Remove 'equals' for table
  colnames(diff_stats) <- c("$F$ ", "$df_1$ ", "$df_2$ ", "$p$ ") # Space enable duplicate row names
  diff_stats <- rbind("", diff_stats)

  model_stats_table <- as.data.frame(
    t(cbind(model_fits, model_diffs[, 1, drop = FALSE], diff_stats, model_diffs[, 2:3]))
    , stringsAsFactors = FALSE
    , make.names = NA
  )
  colnames(model_stats_table) <- names(models)
  apa_res$table <- rbind(coef_table, model_stats_table)
  apa_res$table[is.na(apa_res$table)] <- ""
  class(apa_res$table) <- c("apa_results_table", "data.frame")

  apa_res[c("estimate", "statistic", "full_result")] <- lapply(apa_res[c("estimate", "statistic", "full_result")], as.list)
  apa_res
}
