#= 
    Check the accruacy of the PeTab importer by checking the log-likelihood value against known values for several 
    models.
=#


using ModelingToolkit 
using DifferentialEquations
using DataFrames
using CSV 
using ForwardDiff
using ReverseDiff
using StatsBase
using Random
using LinearAlgebra
using Distributions
using Printf
using SciMLSensitivity
using Zygote
using Symbolics
using Sundials
using FiniteDifferences
using YAML
using Test


# Relevant PeTab structs for compuations 
include(joinpath(pwd(), "src", "PeTab_structs.jl"))

# PeTab importer to get cost, grad etc 
include(joinpath(pwd(), "src", "Create_PEtab_model.jl"))

# HyperCube sampling 
include(joinpath(pwd(), "src", "Optimizers", "Lathin_hypercube.jl"))

# For converting to SBML 
include(joinpath(pwd(), "src", "SBML", "SBML_to_ModellingToolkit.jl"))

solver = Rodas5()
tol = 1e-8

pathYML = "/home/damiano/Distrobox/Debian/Master-thesis/Intermediate/PeTab_models/Smith_BMCSystBiol2013/Smith_BMCSystBiol2013.yaml"

#pathYML = "/home/damiano/Distrobox/Debian/Master-thesis/Intermediate/PeTab_models/model_Bertozzi_PNAS2020/Bertozzi_PNAS2020.yaml"
petabModel = readPEtabModel(pathYML, verbose=false, forceBuildJuliaFiles=true)
petabProblem = setUpPEtabODEProblem(petabModel, solver, solverAbsTol=tol, solverRelTol=tol, 
    sensealgForwardEquations=:AutoDiffForward, odeSolverForwardEquations=solver)

petabProblem.computeCost(rand(Float64, 24))
#
#rand(Float64, 24)
#