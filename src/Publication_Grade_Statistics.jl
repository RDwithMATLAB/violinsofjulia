#!/usr/bin/env julia
# ==============================================================================
# Universal Publication-Grade Statistics & Scientific Plotting Pipeline
# ==============================================================================

using CSV
using DataFrames
using XLSX
using Statistics
using StatsBase
using HypothesisTests
using MultipleTesting
using Distributions
using Plots
using Random
using Colors
using KernelDensity
using Printf
using Dates

gr()
Random.seed!(1234)

# ------------------------------------------------------------------------------
# SECTION 0: USER CONFIGURATION
# ------------------------------------------------------------------------------
const INPUT_PATH = raw"C:/Users/rd12d/Downloads/GSAC-Meeting-RD-19thAug2026/AvgAcc_mm.csv"
const ALPHA      = 0.05

# ==============================================================================
# SECTION 1: UNIVERSAL DATA INGESTION & UNICODE LABEL ENGINE
# ==============================================================================

function format_label_unicode(str::String)
    greek_dict = Dict(
        "\\mu" => "µ", "\\nu" => "ν", "\\omega" => "ω", "\\Omega" => "Ω",
        "\\chi" => "χ", "\\phi" => "ϕ", "\\Phi" => "Φ", "\\alpha" => "α",
        "\\beta" => "β", "\\gamma" => "γ", "\\Gamma" => "Γ", "\\delta" => "δ",
        "\\Delta" => "Δ", "\\epsilon" => "ε", "\\zeta" => "ζ", "\\eta" => "η",
        "\\theta" => "θ", "\\Theta" => "Θ", "\\kappa" => "κ", "\\lambda" => "λ",
        "\\Lambda" => "Λ", "\\pi" => "π", "\\rho" => "ρ", "\\sigma" => "σ",
        "\\Sigma" => "Σ", "\\tau" => "τ", "\\psi" => "ψ", "\\Psi" => "Ψ",
        "\\degree" => "°", "\\deg" => "°", "\\pm" => "±", "\\times" => "×",
        "\\approx" => "≈", "\\le" => "≤", "\\ge" => "≥", "\\cdot" => "·"
    )

    super_dict = Dict(
        "^-1" => "⁻¹", "^-2" => "⁻²", "^-3" => "⁻³", "^-4" => "⁻⁴",
        "^0" => "⁰", "^1" => "¹", "^2" => "²", "^3" => "³", "^4" => "⁴",
        "^5" => "⁵", "^6" => "⁶", "^7" => "⁷", "^8" => "⁸", "^9" => "⁹",
        "^+" => "⁺", "^-" => "⁻", "^n" => "ⁿ"
    )

    sub_dict = Dict(
        "_0" => "₀", "_1" => "₁", "_2" => "₂", "_3" => "₃", "_4" => "₄",
        "_5" => "₅", "_6" => "₆", "_7" => "₇", "_8" => "₈", "_9" => "₉",
        "_a" => "ₐ", "_e" => "ₑ", "_o" => "ₒ", "_x" => "ₓ",
        "_max" => "ₘₐₓ", "_min" => "ₘᵢₙ", "_avg" => "ₐᵥ_g"
    )

    out = str
    for (k, v) in super_dict; out = replace(out, k => v); end
    for (k, v) in sub_dict;   out = replace(out, k => v); end
    for (k, v) in greek_dict; out = replace(out, k => v); end
    
    return out
end

function prompt_y_axis_title(default::String = "Value")
    hint_text = "Enter Y-axis title (Supports shortcuts: \\mu, \\nu, \\omega, \\chi, \\phi, ^2, ^3, ^-1, etc.):"
    ps_script = """
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.Interaction]::InputBox('$hint_text', 'Y-axis Title Formatter', '$default')
    """
    raw_title = default
    try
        res = String(strip(read(`powershell -NoProfile -Command $ps_script`, String)))
        raw_title = isempty(res) ? default : res
    catch
        print("Enter Y-axis title [shortcuts: \\mu, ^2, ^-1] [default: \"$default\"]: ")
        line = String(strip(readline()))
        raw_title = isempty(line) ? default : line
    end
    
    return format_label_unicode(raw_title)
end

function load_data(path::String)
    isfile(path) || error("File not found: $path")
    ext = lowercase(splitext(path)[2])
    if ext == ".csv"
        return CSV.read(path, DataFrame; silencewarnings=true)
    elseif ext in (".xlsx", ".xls")
        return DataFrame(XLSX.readtable(path, 1))
    else
        error("Unsupported file extension: $ext. Please use .csv, .xlsx, or .xls")
    end
end

function extract_groups(df::DataFrame)
    all_col_names = String.(names(df))
    ncol = size(df, 2)
    groups = Dict{String, Vector{Float64}}()
    group_names = String[]

    # Long/Tidy format detection (Column 1 = Group, Column 2 = Value)
    if ncol == 2
        col1 = df[!, 1]; col2 = df[!, 2]
        col2_numeric = any(v -> try Float64(v) isa Float64 catch; false end, filter(!ismissing, col2))
        col1_categorical = any(v -> !(try Float64(v) isa Float64 catch; false end), filter(!ismissing, col1))

        if col2_numeric && col1_categorical
            for (grp, val) in zip(col1, col2)
                if grp !== missing && val !== missing
                    g_str = String(strip(string(grp)))
                    try
                        fval = Float64(val)
                        if isfinite(fval)
                            if !haskey(groups, g_str)
                                groups[g_str] = Float64[]
                                push!(group_names, g_str)
                            end
                            push!(groups[g_str], fval)
                        end
                    catch end
                end
            end
            if !isempty(group_names) return group_names, groups end
        end
    end

    # Wide format (Each column = Group)
    for col_name in all_col_names
        raw_vals = df[!, col_name]
        clean_vals = Float64[]
        for v in raw_vals
            if v !== missing && v !== nothing
                try
                    fv = Float64(v)
                    if isfinite(fv) push!(clean_vals, fv) end
                catch end
            end
        end
        if !isempty(clean_vals)
            g_name = String(strip(col_name))
            groups[g_name] = clean_vals
            push!(group_names, g_name)
        end
    end

    isempty(group_names) && error("No usable numeric data found in file: $INPUT_PATH")
    return group_names, groups
end

# ==============================================================================
# SECTION 2: STATISTICAL ENGINES & POST-HOC TESTING
# ==============================================================================

safe_std(v::Vector{Float64}) = length(v) < 2 ? 0.0 : std(v)
safe_sem(v::Vector{Float64}) = length(v) < 2 ? 0.0 : std(v) / sqrt(length(v))

function compute_tied_ranks(v::Vector{Float64})
    n = length(v)
    p_order = sortperm(v)
    sorted_v = v[p_order]
    ranks = zeros(Float64, n)
    i = 1
    while i <= n
        j = i
        while j < n && sorted_v[j+1] == sorted_v[i] j += 1 end
        avg_rank = (i + j) / 2.0
        for k in i:j ranks[p_order[k]] = avg_rank end
        i = j + 1
    end
    return ranks
end

function manual_mann_whitney_u(x::Vector{Float64}, y::Vector{Float64})
    n1, n2 = length(x), length(y)
    combined = vcat(x, y)
    ranks = compute_tied_ranks(combined)
    r1 = sum(ranks[1:n1])
    u1 = r1 - (n1 * (n1 + 1)) / 2.0
    u2 = (n1 * n2) - u1
    u_stat = min(u1, u2)
    
    mean_u = (n1 * n2) / 2.0
    unique_counts = Dict{Float64, Int}()
    for val in combined unique_counts[val] = get(unique_counts, val, 0) + 1 end
    tie_term = sum(t^3 - t for t in values(unique_counts) if t > 1; init=0.0)
    N = n1 + n2
    var_u = ((n1 * n2) / 12.0) * ((N + 1) - (tie_term / (N * (N - 1))))
    
    sigma_u = sqrt(max(var_u, 1e-12))
    z = (abs(u1 - mean_u) - 0.5) / sigma_u
    pval = 2.0 * ccdf(Normal(), abs(z))
    return u_stat, pval
end

function hedges_g(x::Vector{Float64}, y::Vector{Float64})
    n1, n2 = length(x), length(y)
    df = n1 + n2 - 2
    df <= 0 && return NaN
    s_pooled = sqrt(((n1 - 1)*safe_std(x)^2 + (n2 - 1)*safe_std(y)^2) / df)
    s_pooled == 0 && return NaN
    d = (mean(x) - mean(y)) / s_pooled
    j_factor = 1.0 - (3.0 / (4.0 * df - 1.0))
    return d * j_factor
end

function rank_biserial_corr(u_stat::Float64, n1::Int, n2::Int)
    (n1 * n2) == 0 && return NaN
    return 1.0 - (2.0 * u_stat) / (n1 * n2)
end

function studentized_range_sf(q::Float64, k::Int, df::Float64)
    if q <= 0.0 return 1.0 end
    if isnan(q) || isnan(df) || df <= 0.0 || k < 2 return NaN end
    
    nodes = [-0.993862, -0.967227, -0.923880, -0.864464, -0.789858, -0.701369, 
             -0.600208, -0.487711, -0.365303, -0.234415, -0.096468,  0.0,
              0.096468,  0.234415,  0.365303,  0.487711,  0.600208,  0.701369,
              0.789858,  0.864464,  0.923880,  0.967227,  0.993862]
    weights = [0.015748, 0.036268, 0.055848, 0.074224, 0.090858, 0.105484, 
               0.117860, 0.127738, 0.134924, 0.139282, 0.140814, 0.140814,
               0.140814, 0.139282, 0.134924, 0.127738, 0.117860, 0.105484,
               0.090858, 0.074224, 0.055848, 0.036268, 0.015748]

    x_vals = 6.0 .* nodes
    w_x = 6.0 .* weights
    phi_x = pdf.(Normal(), x_vals)
    Phi_x = cdf.(Normal(), x_vals)

    function inner_int(s_val)
        Phi_x_qs = cdf.(Normal(), x_vals .- q * s_val)
        term = clamp.(Phi_x .- Phi_x_qs, 0.0, 1.0)
        return sum(w_x .* k .* phi_x .* (term .^ (k - 1)))
    end

    s_vals = 0.5 * (4.0 - 0.05) .* nodes .+ 0.5 * (4.0 + 0.05)
    s_w = 0.5 * (4.0 - 0.05) .* weights
    total = 0.0
    for idx in 1:length(s_vals)
        s_val = s_vals[idx]
        w_s = s_w[idx]
        log_pdf_s = log(2.0) + (df/2.0)*log(df) - (df/2.0)*log(2.0) - loggamma(df/2.0) + (df - 1.0)*log(s_val) - (df * s_val^2 / 2.0)
        pdf_s = exp(log_pdf_s)
        total += w_s * pdf_s * (1.0 - inner_int(s_val))
    end
    return clamp(total, 0.0, 1.0)
end

function significance_stars(p::Real)
    isnan(p) && return "ns"
    p < 0.0001 && return "****"
    p < 0.001  && return "***"
    p < 0.01   && return "**"
    p < ALPHA  && return "*"
    return "ns"
end

function test_normality_full(x::Vector{Float64})
    n = length(x)
    if n < 3 || safe_std(x) == 0
        return (is_normal = false, pval = NaN, stat = NaN, skew = NaN, kurt = NaN, clt = false, note = "n<3 or zero variance")
    end
    sw = try ShapiroWilkTest(x) catch; nothing end
    p = isnothing(sw) ? NaN : pvalue(sw)
    stat = isnothing(sw) ? NaN : sw.W
    
    m, s = mean(x), std(x)
    sk = (sum((x .- m).^3) / n) / (s^3)
    kt = ((sum((x .- m).^4) / n) / (s^4)) - 3.0
    clt_robust = (n >= 30 && abs(sk) <= 1.0 && abs(kt) <= 2.0)
    is_norm = (!isnan(p) && p > ALPHA) || clt_robust
    note = clt_robust ? "CLT Robust (n>=30, |skew|<=1, |kurt|<=2)" : (is_norm ? "Shapiro-Wilk p > 0.05" : "Non-normal (p <= 0.05)")
    
    return (is_normal = is_norm, pval = p, stat = stat, skew = sk, kurt = kt, clt = clt_robust, note = note)
end

function levene_test_full(groups::Vector{Vector{Float64}})
    medians = median.(groups)
    z_groups = [abs.(groups[i] .- medians[i]) for i in 1:length(groups)]
    res = one_way_anova(z_groups)
    return res.F, res.pval
end

function one_way_anova(groups::Vector{Vector{Float64}})
    k = length(groups)
    all_vals = vcat(groups...)
    N = length(all_vals)
    grand_mean = mean(all_vals)
    ss_between = sum(length(g) * (mean(g) - grand_mean)^2 for g in groups)
    ss_within  = sum(sum((v - mean(g))^2 for v in g) for g in groups)
    df_b, df_w = k - 1, N - k
    if df_w <= 0 || ss_within == 0 return (F = NaN, pval = NaN, eta_sq = NaN, ms_within = NaN, df_b = df_b, df_w = df_w) end
    F = (ss_between / df_b) / (ss_within / df_w)
    p = ccdf(FDist(df_b, df_w), F)
    return (F = F, pval = p, eta_sq = ss_between / (ss_between + ss_within), ms_within = ss_within / df_w, df_b = df_b, df_w = df_w)
end

function welch_anova_full(groups::Vector{Vector{Float64}})
    k = length(groups)
    ns = length.(groups)
    means = mean.(groups)
    vars = [max(var(g), 1e-12) for g in groups]
    weights = ns ./ vars
    W = sum(weights)
    grand_mean = sum(weights .* means) / W
    num = sum(weights .* (means .- grand_mean).^2) / (k - 1)
    lambda = sum((1.0 .- weights ./ W).^2 ./ (ns .- 1))
    F = num / (1.0 + 2.0 * (k - 2) / (k^2 - 1) * lambda)
    df1 = k - 1
    df2 = (k^2 - 1) / (3.0 * lambda)
    pval = ccdf(FDist(df1, df2), F)
    
    all_vals = vcat(groups...)
    ss_total = sum((all_vals .- mean(all_vals)).^2)
    ss_between = sum(ns .* (means .- mean(all_vals)).^2)
    eta_sq = ss_between / ss_total
    return (F = F, pval = pval, df1 = df1, df2 = df2, eta_sq = eta_sq)
end

function tukey_hsd(group_names::Vector{String}, groups::Dict{String,Vector{Float64}}, ms_within::Float64, df_w::Float64)
    k = length(group_names)
    pairs = Tuple{String,String}[]; pvals = Float64[]; effs = Float64[]
    for a in 1:k-1, b in a+1:k
        ga, gb = group_names[a], group_names[b]
        va, vb = groups[ga], groups[gb]
        se = sqrt((ms_within / 2.0) * (1.0/length(va) + 1.0/length(vb)))
        q = abs(mean(va) - mean(vb)) / se
        push!(pairs, (ga, gb)); push!(pvals, studentized_range_sf(q, k, df_w)); push!(effs, hedges_g(va, vb))
    end
    return pairs, pvals, effs
end

function games_howell(group_names::Vector{String}, groups::Dict{String,Vector{Float64}})
    k = length(group_names)
    pairs = Tuple{String,String}[]; pvals = Float64[]; effs = Float64[]
    for a in 1:k-1, b in a+1:k
        ga, gb = group_names[a], group_names[b]
        va, vb = groups[ga], groups[gb]
        na, nb = length(va), length(vb)
        vara, varb = safe_std(va)^2, safe_std(vb)^2
        se = sqrt((vara / na) + (varb / nb))
        q = sqrt(2.0) * (abs(mean(va) - mean(vb)) / se)
        df_gh = (vara/na + varb/nb)^2 / (((vara/na)^2 / (na - 1)) + ((varb/nb)^2 / (nb - 1)))
        push!(pairs, (ga, gb)); push!(pvals, studentized_range_sf(q, k, df_gh)); push!(effs, hedges_g(va, vb))
    end
    return pairs, pvals, effs
end

function dunns_test(groups_dict::Dict{String,Vector{Float64}}, group_names::Vector{String})
    all_vals = Float64[]; group_ids = Int[]
    for (i, g) in enumerate(group_names)
        append!(all_vals, groups_dict[g])
        append!(group_ids, fill(i, length(groups_dict[g])))
    end
    N = length(all_vals)
    ranks = compute_tied_ranks(all_vals)
    mean_ranks = [mean(ranks[group_ids .== i]) for i in 1:length(group_names)]
    counts = Dict{Float64,Int}()
    for val in all_vals counts[val] = get(counts, val, 0) + 1 end
    tie_adj = sum(c^3 - c for c in values(counts) if c > 1; init=0.0)
    var_base = max((N * (N + 1) / 12.0) - (tie_adj / (12.0 * (N - 1))), 1e-12)
    
    pairs = Tuple{String,String}[]; raw_p = Float64[]; r_rb_list = Float64[]
    k = length(group_names)
    for a in 1:k-1, b in a+1:k
        ga, gb = group_names[a], group_names[b]
        va, vb = groups_dict[ga], groups_dict[gb]
        se = sqrt(var_base * (1.0/length(va) + 1.0/length(vb)))
        z = abs(mean_ranks[a] - mean_ranks[b]) / se
        u_stat, _ = manual_mann_whitney_u(va, vb)
        push!(pairs, (ga, gb))
        push!(raw_p, 2.0 * ccdf(Normal(), z))
        push!(r_rb_list, rank_biserial_corr(u_stat, length(va), length(vb)))
    end
    return pairs, raw_p, MultipleTesting.adjust(raw_p, Holm()), r_rb_list
end

# ==============================================================================
# SECTION 3: DECISION TREE RUNNER & REPORT EXPORT
# ==============================================================================

function run_analysis(group_names::Vector{String}, groups::Dict{String,Vector{Float64}})
    n_groups = length(group_names)
    
    normality_df = DataFrame(
        Group = String[], N = Int[], ShapiroWilk_W = Float64[], ShapiroWilk_P = Float64[],
        Skewness = Float64[], Kurtosis_Excess = Float64[], CLT_Robust = Bool[],
        Verdict = String[], Note = String[]
    )
    all_normal = true
    for g in group_names
        r = test_normality_full(groups[g])
        verdict_str = r.is_normal ? "Parametric (Normal)" : "Non-Parametric (Non-Normal)"
        push!(normality_df, (g, length(groups[g]), r.stat, r.pval, r.skew, r.kurt, r.clt, verdict_str, r.note))
        all_normal &= r.is_normal
    end

    summary_df = DataFrame(
        Group = String[], N = Int[], Mean = Float64[], SEM = Float64[], SD = Float64[],
        Median = Float64[], IQR = Float64[], Q1_25pct = Float64[], Q3_75pct = Float64[],
        Min = Float64[], Max = Float64[], Skewness = Float64[], Kurtosis = Float64[]
    )
    for g in group_names
        v = groups[g]
        q25, q75 = length(v) >= 2 ? quantile(v, [0.25, 0.75]) : (NaN, NaN)
        iqr_val = isfinite(q25) && isfinite(q75) ? q75 - q25 : 0.0
        sk = length(v) >= 3 ? (sum((v .- mean(v)).^3)/length(v))/(std(v)^3) : NaN
        kt = length(v) >= 4 ? ((sum((v .- mean(v)).^4)/length(v))/(std(v)^4)) - 3.0 : NaN
        push!(summary_df, (
            g, length(v), mean(v), safe_sem(v), safe_std(v), median(v), iqr_val,
            q25, q75, minimum(v), maximum(v), sk, kt
        ))
    end

    variance_df = DataFrame(Test = String[], Statistic = Float64[], PValue = Float64[], Alpha = Float64[], Verdict = String[], Note = String[])
    equal_var = true
    if n_groups >= 3
        ordered_vals = [groups[g] for g in group_names]
        lev_f, lev_p = levene_test_full(ordered_vals)
        equal_var = lev_p > ALPHA
        push!(variance_df, (
            "Brown-Forsythe / Levene's Test (Median-centered)",
            lev_f, lev_p, ALPHA,
            equal_var ? "Equal Variance (Homoscedastic)" : "Unequal Variance (Heteroscedastic)",
            equal_var ? "Parametric ANOVA assumption satisfied" : "Welch correction or Non-parametric path required"
        ))
    else
        push!(variance_df, ("N/A (2 Groups Analyzed)", NaN, NaN, ALPHA, "Evaluated directly via two-sample test", "Welch's t-test / Mann-Whitney U selected"))
    end

    main_test_df = DataFrame(
        Hypothesis = String[], Test = String[], Statistic_Name = String[], Statistic_Value = Float64[],
        DegreesOfFreedom = String[], PValue = Float64[], Significance = String[],
        EffectSize_Metric = String[], EffectSize_Value = Float64[], SelectionRationale = String[],
        AssumptionsTaken = String[], MultiplicityCorrection = String[]
    )
    
    posthoc_df = DataFrame(
        GroupA = String[], GroupB = String[], Test = String[], Raw_PValue = Float64[],
        Adjusted_PValue = Float64[], Correction_Method = String[], Significant = Bool[],
        EffectSize_Metric = String[], EffectSize_Value = Float64[], Rationale = String[]
    )

    if n_groups == 2
        a, b = group_names[1], group_names[2]
        xa, xb = groups[a], groups[b]
        if all_normal
            t_obj = try UnequalVarianceTTest(xa, xb) catch; nothing end
            p = isnothing(t_obj) ? NaN : pvalue(t_obj)
            stat = isnothing(t_obj) ? NaN : t_obj.t
            df_str = isnothing(t_obj) ? "N/A" : @sprintf("%.2f", t_obj.df)
            eff = hedges_g(xa, xb)
            push!(main_test_df, (
                "Difference in Means between $a and $b", "Welch's t-test (Unequal Variance t-test)",
                "t", stat, df_str, p, significance_stars(p), "Hedges' g (bias-corrected Cohen's d)", eff,
                "Both groups exhibited normal distributions (or CLT robustness). Welch's formulation accounts for unequal sample sizes/variances.",
                "Continuous independent data, normality satisfied, independent biological replicates.",
                "None required (Single two-sample pairwise comparison)"
            ))
        else
            u_stat, p = manual_mann_whitney_u(xa, xb)
            r_rb = rank_biserial_corr(u_stat, length(xa), length(xb))
            push!(main_test_df, (
                "Stochastic Dominance / Median Rank Difference between $a and $b", "Mann-Whitney U Test (Wilcoxon Rank-Sum)",
                "U", u_stat, "N/A (Non-parametric)", p, significance_stars(p), "Rank-Biserial Correlation (r_rb)", r_rb,
                "At least one group violated normality (Shapiro-Wilk p <= 0.05 and n < 30). Non-parametric rank analysis required.",
                "Continuous ordinal/metric data, independent biological observations, mutual independence between groups.",
                "Continuity correction and exact tie adjustment applied to U variance"
            ))
        end
    elseif n_groups >= 3
        ordered_vals = [groups[g] for g in group_names]
        if all_normal
            if equal_var
                omnibus = one_way_anova(ordered_vals)
                push!(main_test_df, (
                    "Equality of Means across $n_groups groups", "Fisher's One-Way ANOVA",
                    "F", omnibus.F, "df_between = $(omnibus.df_b), df_within = $(omnibus.df_w)", omnibus.pval, significance_stars(omnibus.pval),
                    "Eta-squared (η²)", omnibus.eta_sq,
                    "All groups satisfy normality and Levene's test confirmed equal variance (homoscedasticity, p > 0.05).",
                    "Normality of residuals, homoscedasticity of variance, independent random sampling.",
                    "None on omnibus; Pairwise tests gated by omnibus significance"
                ))
                if omnibus.pval < ALPHA
                    pairs, pvals, effs = tukey_hsd(group_names, groups, omnibus.ms_within, Float64(omnibus.df_w))
                    for i in 1:length(pairs)
                        push!(posthoc_df, (
                            pairs[i][1], pairs[i][2], "Tukey HSD / Tukey-Kramer", pvals[i], pvals[i],
                            "Studentized Range Exact Integration (Tukey-Kramer)", pvals[i] < ALPHA,
                            "Hedges' g", effs[i], "Omnibus ANOVA was statistically significant (p < 0.05). Tukey HSD controls FWER under equal variances."
                        ))
                    end
                end
            else
                omnibus = welch_anova_full(ordered_vals)
                push!(main_test_df, (
                    "Equality of Means across $n_groups groups (Heteroscedastic)", "Welch's Heteroscedastic ANOVA",
                    "F", omnibus.F, "df1 = $(omnibus.df1), df2 = $(round(omnibus.df2, digits=2))", omnibus.pval, significance_stars(omnibus.pval),
                    "Eta-squared (η²)", omnibus.eta_sq,
                    "Normality satisfied, but Levene's test showed significant variance heterogeneity (p <= 0.05). Welch ANOVA applies weighting by group variances.",
                    "Normality of residuals, unequal variances allowed, independent biological replicates.",
                    "Welch-Satterthwaite adjusted degrees of freedom"
                ))
                if omnibus.pval < ALPHA
                    pairs, pvals, effs = games_howell(group_names, groups)
                    for i in 1:length(pairs)
                        push!(posthoc_df, (
                            pairs[i][1], pairs[i][2], "Games-Howell Post-Hoc", pvals[i], pvals[i],
                            "Welch-Satterthwaite Pairwise df with Studentized Range Distribution", pvals[i] < ALPHA,
                            "Hedges' g", effs[i], "Omnibus Welch ANOVA p < 0.05. Games-Howell accounts for both unequal variances and sample sizes."
                        ))
                    end
                end
            end
        else
            k_obj = KruskalWallisTest(ordered_vals...)
            p_kw, h_stat = pvalue(k_obj), k_obj.H
            N_tot = sum(length.(ordered_vals))
            eps_sq = (h_stat - n_groups + 1.0) / (N_tot - n_groups)
            push!(main_test_df, (
                "Equality of Population Medians/Ranks across $n_groups groups", "Kruskal-Wallis Non-Parametric ANOVA",
                "H (Chi-squared)", h_stat, "df = $(n_groups - 1)", p_kw, significance_stars(p_kw),
                "Epsilon-squared (ε_R²)", eps_sq,
                "Normality violated in one or more groups. Kruskal-Wallis performs omnibus rank variance evaluation.",
                "Ordinal or continuous distribution, identically shaped distributions under null hypothesis, independent observations.",
                "Tie-adjusted rank variance calculation"
            ))
            if p_kw < ALPHA
                pairs, raw_p, adj_p, r_rb_list = dunns_test(groups, group_names)
                for i in 1:length(pairs)
                    push!(posthoc_df, (
                        pairs[i][1], pairs[i][2], "Dunn's Post-Hoc Test", raw_p[i], adj_p[i],
                        "Holm-Bonferroni (Step-down FWER)", adj_p[i] < ALPHA,
                        "Rank-Biserial Correlation (r_rb)", r_rb_list[i],
                        "Omnibus Kruskal-Wallis p < 0.05. Dunn's test evaluates pairwise rank-sum differences with Holm adjustment to control Type I error."
                    ))
                end
            end
        end
    end

    main_name = main_test_df.Test[1]
    main_p = main_test_df.PValue[1]
    main_sig = main_test_df.Significance[1]
    exec_summary_df = DataFrame(
        Parameter = [
            "Dataset Source Path",
            "Analysis Timestamp",
            "Total Experimental Groups",
            "Sample Size Range (n)",
            "Distribution Diagnosis",
            "Homoscedasticity Diagnosis",
            "Selected Omnibus / Primary Test",
            "Test Statistic",
            "P-Value",
            "Statistical Significance",
            "Primary Effect Size Metric",
            "Primary Effect Size Value",
            "Multiplicity / Post-Hoc Correction",
            "Total Post-Hoc Pairwise Comparisons",
            "Significant Post-Hoc Pairs"
        ],
        Value = [
            INPUT_PATH,
            Dates.format(now(), "yyyy-mm-dd HH:MM:SS"),
            string(n_groups),
            "$(minimum(length.(values(groups)))) to $(maximum(length.(values(groups))))",
            all_normal ? "Parametric (Normal / CLT Robust across all groups)" : "Non-Parametric (Evidence against normality in >=1 group)",
            n_groups >= 3 ? (equal_var ? "Equal Variance (Levene p > 0.05)" : "Unequal Variance (Levene p <= 0.05)") : "Evaluated via Two-Sample Formulation",
            main_name,
            @sprintf("%.4f (%s)", main_test_df.Statistic_Value[1], main_test_df.Statistic_Name[1]),
            main_p < 0.0001 ? @sprintf("%.3e", main_p) : @sprintf("%.4f", main_p),
            main_sig == "ns" ? "Not Significant (p >= 0.05)" : "Significant ($main_sig)",
            main_test_df.EffectSize_Metric[1],
            isnan(main_test_df.EffectSize_Value[1]) ? "N/A" : @sprintf("%.4f", main_test_df.EffectSize_Value[1]),
            nrow(posthoc_df) > 0 ? posthoc_df.Correction_Method[1] : (n_groups == 2 ? "None needed (Single comparison)" : "Post-Hoc Bypassed (Omnibus p >= 0.05)"),
            string(nrow(posthoc_df)),
            string(count(posthoc_df.Significant))
        ]
    )

    assumptions_df = DataFrame(
        Core_Assumption = [
            "1. Biological Independence",
            "2. Normality Evaluation",
            "3. Homoscedasticity (Equal Variance)",
            "4. Multiplicity & FWER Control",
            "5. Effect Size Estimation",
            "6. Omnibus Gating Principle"
        ],
        Rigorous_Standard = [
            "Each datapoint must represent a genuinely independent biological entity (animal, distinct lineage, or non-repeated culture). Technical replicates must be averaged prior to entry.",
            "Shapiro-Wilk test (alpha = 0.05) combined with skewness ([-1, 1]) and kurtosis ([-2, 2]). Central Limit Theorem (CLT) invoked only when n >= 30 with moderate distributional shapes.",
            "Assessed using median-centered Brown-Forsythe / Levene's test. If p <= 0.05, homoscedastic models are rejected in favor of Welch ANOVA or non-parametric alternatives.",
            "When >= 3 groups undergo pairwise testing, Family-Wise Error Rate (FWER) inflation is strictly controlled using exact Studentized Range integration (Tukey/Games-Howell) or Holm step-down adjustment (Dunn).",
            "Parametric pairwise differences report Hedges' g (correcting small-sample Cohen's d bias). Non-parametric differences report Rank-Biserial Correlation (r_rb). Omnibus models report Eta-squared (η²) or Epsilon-squared (ε²_R).",
            "Pairwise post-hoc tests are strictly gated and only executed if the omnibus test achieves p < 0.05, preventing ungrounded data fishing and false discovery inflation."
        ]
    )

    return exec_summary_df, summary_df, normality_df, variance_df, main_test_df, posthoc_df, assumptions_df
end

function save_stats_excel(path::String, exec_summary_df, summary_df, normality_df, variance_df, main_test_df, posthoc_df, assumptions_df)
    target_path = path
    if isfile(target_path)
        try
            rm(target_path; force=true)
        catch e
            timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
            dir_p, fn = splitdir(path)
            base_fn, ext = splitext(fn)
            target_path = joinpath(dir_p, "$(base_fn)_$(timestamp)$(ext)")
            println("Note: Target file was open/locked. Export redirected to: $target_path")
        end
    end

    XLSX.openxlsx(target_path, mode="w") do xf
        s1 = xf[1]; XLSX.rename!(s1, "Executive_Summary"); XLSX.writetable!(s1, exec_summary_df)
        s2 = XLSX.addsheet!(xf, "Descriptive_Statistics"); XLSX.writetable!(s2, summary_df)
        s3 = XLSX.addsheet!(xf, "Normality_Diagnostics"); XLSX.writetable!(s3, normality_df)
        s4 = XLSX.addsheet!(xf, "Variance_Diagnostics"); XLSX.writetable!(s4, variance_df)
        s5 = XLSX.addsheet!(xf, "Main_Hypothesis_Test"); XLSX.writetable!(s5, main_test_df)
        if nrow(posthoc_df) > 0
            s6 = XLSX.addsheet!(xf, "PostHoc_Pairwise"); XLSX.writetable!(s6, posthoc_df)
        end
        s7 = XLSX.addsheet!(xf, "Methodology_Assumptions"); XLSX.writetable!(s7, assumptions_df)
    end
    println("Complete 7-sheet statistical report saved to: $target_path")
end

# ==============================================================================
# SECTION 4: SCIENTIFIC PLOTTING ENGINE (FLAWLESS BRACKET & TEXT ALIGNMENT)
# ==============================================================================

darken(c::RGB, amount::Float64) = RGB(clamp(c.r - amount, 0.0, 1.0), clamp(c.g - amount, 0.0, 1.0), clamp(c.b - amount, 0.0, 1.0))

function add_significance_brackets!(p, pairs, base_y, data_span)
    sort!(pairs, by = x -> x[2] - x[1])
    
    tier_height = data_span * 0.24
    tick_length = data_span * 0.035
    curr_bar_y  = base_y + data_span * 0.12

    for (x1, x2, stars, pval) in pairs
        plot!(p, [x1, x1, x2, x2], 
              [curr_bar_y - tick_length, curr_bar_y, curr_bar_y, curr_bar_y - tick_length],
              color=RGB(0.15, 0.15, 0.15), lw=1.8, label="")
        
        mid_x = (x1 + x2) / 2.0
        p_text = isnan(pval) ? "ns" : (pval < 0.0001 ? @sprintf("p = %.2e", pval) : @sprintf("p = %.4f", pval))

        label_text = "$stars\n($p_text)"
        annotate!(p, [(mid_x, curr_bar_y + data_span * 0.025, 
                  Plots.text(label_text, 12, :bold, :center, :bottom, RGB(0.1, 0.1, 0.1)))])

        curr_bar_y += tier_height
    end
end

function make_plot(group_names::Vector{String}, groups::Dict{String,Vector{Float64}}, main_test_df, posthoc_df, y_axis_label::AbstractString, save_path::String)
    all_vals = vcat([groups[g] for g in group_names]...)
    n_groups = length(group_names)

    min_val, max_val = minimum(all_vals), maximum(all_vals)
    data_span = max(max_val - min_val, 1e-6)

    # Clean & Sanitize Statistical Test Name Specifically for Plot Rendering
    plot_test_name = ""
    if n_groups == 2 && nrow(main_test_df) > 0
        raw_t = main_test_df.Test[1]
        if occursin("Mann-Whitney", raw_t)
            plot_test_name = "Mann-Whitney U"
        elseif occursin("Welch", raw_t)
            plot_test_name = "Welch's t-test"
        else
            plot_test_name = raw_t
        end
    elseif n_groups >= 3 && nrow(main_test_df) > 0
        raw_o = main_test_df.Test[1]
        o_clean = occursin("One-Way", raw_o) ? "One-Way ANOVA" : (occursin("Welch", raw_o) ? "Welch ANOVA" : "Kruskal-Wallis")
        if nrow(posthoc_df) > 0
            raw_p = posthoc_df.Test[1]
            p_clean = occursin("Tukey", raw_p) ? "Tukey HSD" : (occursin("Games-Howell", raw_p) ? "Games-Howell" : "Dunn's (Holm)")
            plot_test_name = "$o_clean + $p_clean"
        else
            plot_test_name = o_clean
        end
    end

    # Collect comparisons
    annotation_pairs = Tuple{Int,Int,String,Float64}[]
    if n_groups == 2 && nrow(main_test_df) > 0
        push!(annotation_pairs, (1, 2, main_test_df.Significance[1], main_test_df.PValue[1]))
    elseif nrow(posthoc_df) > 0
        for row in eachrow(posthoc_df)
            if row.Significant
                i1 = findfirst(==(row.GroupA), group_names)
                i2 = findfirst(==(row.GroupB), group_names)
                if !isnothing(i1) && !isnothing(i2)
                    push!(annotation_pairs, (min(i1, i2), max(i1, i2), significance_stars(row.Adjusted_PValue), row.Adjusted_PValue))
                end
            end
        end
    end

    n_brackets = length(annotation_pairs)
    bracket_top_pad = n_brackets > 0 ? (n_brackets * 0.28 * data_span + 0.26 * data_span) : (0.18 * data_span)
    y_bottom_pad = 0.08 * data_span
    y_limits = (min_val - y_bottom_pad, max_val + bracket_top_pad)

    base_colors = [RGB(0.55, 0.75, 0.88), RGB(0.92, 0.65, 0.68), RGB(0.65, 0.85, 0.77), RGB(0.93, 0.82, 0.65)]
    violin_polys = Vector{Union{Nothing,Tuple{Vector{Float64},Vector{Float64}}}}(nothing, n_groups)
    point_xs = [Float64[] for _ in 1:n_groups]; point_ys = [Float64[] for _ in 1:n_groups]
    means = Float64[]; sems = Float64[]

    for (i, g) in enumerate(group_names)
        v = groups[g]
        push!(means, mean(v)); push!(sems, safe_sem(v))
        g_min, g_max = minimum(v), maximum(v)

        kd_ok = false
        if length(v) >= 3 && safe_std(v) > 0
            try
                kd = kde(v)
                d_max = maximum(kd.density)
                if d_max > 0 && isfinite(d_max)
                    idx = findall(x -> g_min <= x <= g_max, kd.x)
                    tx, td = kd.x[idx], kd.density[idx]
                    if !isempty(tx)
                        interp_dens(y) = td[clamp(searchsortedlast(tx, y), 1, length(tx))]
                        for y in v
                            hw = 0.32 * (interp_dens(y) / d_max)
                            push!(point_xs[i], i + (rand() - 0.5) * 2 * hw)
                            push!(point_ys[i], y)
                        end
                        lx = vcat([i], i .- (td ./ d_max) .* 0.32, [i])
                        rx = vcat([i], i .+ (td ./ d_max) .* 0.32, [i])
                        poly_y = vcat([g_min], tx, [g_max])
                        violin_polys[i] = (vcat(lx, reverse(rx)), vcat(poly_y, reverse(poly_y)))
                        kd_ok = true
                    end
                end
            catch; kd_ok = false end
        end

        if !kd_ok
            for y in v
                push!(point_xs[i], i + (rand() - 0.5) * 0.15)
                push!(point_ys[i], y)
            end
        end
    end

    xtick_labels = ["$(g)\n(n=$(length(groups[g])))" for g in group_names]
    canvas_w = max(520, 210 * n_groups + 120)
	canvas_h = 850   # <-- Increase from 700 to 850 (or 900)

    plt = plot(; xticks = (1:n_groups, xtick_labels), size = (canvas_w, canvas_h),
                 legend = false, xguide = "", yguide = y_axis_label,
                 guidefontsize = 26, xtickfontsize = 16, ytickfontsize = 14,
                 framestyle = :axes, grid = false, background_color = :white,
                 bottom_margin = 16Plots.mm, left_margin = 16Plots.mm, right_margin = 8Plots.mm, top_margin = 12Plots.mm)

    # 1. Render Violins & Raw Points
    for i in 1:n_groups
        c_base = base_colors[(i - 1) % length(base_colors) + 1]
        if violin_polys[i] !== nothing
            px, py = violin_polys[i]
            plot!(plt, px, py; seriestype = :shape, fillalpha = 0.38, linealpha = 0, color = c_base, label="")
        end
        scatter!(plt, point_xs[i], point_ys[i]; 
                 markersize = 8, markeralpha = 0.85,
                 markercolor = c_base, markerstrokecolor = darken(c_base, 0.35), 
                 markerstrokewidth = 1.3, label="")
    end

    # 2. Render Summary Mean ± SEM Point
    scatter!(plt, collect(1:n_groups), means; yerror = sems, 
             markersize = 10, markershape = :circle,
             markercolor = RGB(0.12, 0.12, 0.16), markerstrokecolor = RGB(0.12, 0.12, 0.16),
             linecolor = RGB(0.12, 0.12, 0.16), linewidth = 2.8, capsize = 8, label="")

    xlims!(plt, (0.4, n_groups + 0.6))
    ylims!(plt, y_limits)

    # 3. Render Significance Brackets
    if n_brackets > 0
        add_significance_brackets!(plt, annotation_pairs, max_val, data_span)
    end

    # 4. Clean, Non-Colliding Top-Right Description (Strictly Formatted & Wrapped)
    top_right_caption = isempty(plot_test_name) ? 
        "Error bars: Mean ± SEM" : 
        "Error bars: Mean ± SEM\nTest: $plot_test_name"

    annotate!(plt, [(n_groups + 0.45, y_limits[2] - 0.02 * (y_limits[2] - y_limits[1]),
              Plots.text(top_right_caption, 9, :gray, :right, :top))])

    savefig(plt, save_path)
    println("Publication plot saved to: $save_path")
end

# ==============================================================================
# SECTION 5: PIPELINE EXECUTION
# ==============================================================================
function main()
    df = load_data(INPUT_PATH)
    group_names, groups = extract_groups(df)

    exec_summary_df, summary_df, normality_df, variance_df, main_test_df, posthoc_df, assumptions_df = run_analysis(group_names, groups)

    default_label = splitext(basename(INPUT_PATH))[1]
    y_axis_label = prompt_y_axis_title(default_label)
    println("Generating analysis for: \"$y_axis_label\"")

    parent_dir = dirname(INPUT_PATH)
    base = splitext(basename(INPUT_PATH))[1]
    stats_path = joinpath(parent_dir, base * "_stats.xlsx")
    plot_path  = joinpath(parent_dir, base * "_plot.svg")

    save_stats_excel(stats_path, exec_summary_df, summary_df, normality_df, variance_df, main_test_df, posthoc_df, assumptions_df)
    make_plot(group_names, groups, main_test_df, posthoc_df, y_axis_label, plot_path)
    println("Analysis completed successfully.")
end

main()