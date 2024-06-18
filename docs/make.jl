using EXR
using Documenter

DocMeta.setdocmeta!(EXR, :DocTestSetup, :(using EXR); recursive=true)

makedocs(;
    modules=[EXR],
    authors="Cédric BELMANT",
    sitename="EXR.jl",
    format=Documenter.HTML(;
        canonical="https://serenity4.github.io/EXR.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/serenity4/EXR.jl",
    devbranch="main",
)
