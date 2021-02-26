
using LinearAlgebra
using PyCall
fugashi = pyimport("fugashi")
const LemmaINDEX = 8

function Summarize(document::T where T<:AbstractString; threshold=0.1, mmr_l=0.8, igpref=4)
    
    splited_document = Tuple(
        sentence 
        for sentence in split(replace(document, "。"=>"。\n"), "\n")
        if sentence != "" || match(r"^[ ]+$", sentence) === nothing
    )
    sentences = tokenize(splited_document, igpref=igpref)
    rated = lexrank(sentences, threshold, mmr_l)
    #println(scores)
    return ((score, splited_document[i]) for (i,score) in rated)
end

function tokenize(texts; igpref=4)
    tagger = fugashi.Tagger("-Owakati")
    resultarray = fill([""], length(texts))
    for (i, text) in enumerate(texts)
        sentence::Array{String, 1} = []
        tagger.parse(text)
        for (i, word) in enumerate(tagger(text))
            i < igpref && continue
            w = word.feature[LemmaINDEX]
            w = typeof(w) != String ? word.surface : w
            word.feature[1] in ("名詞", "形容詞",) || continue
            #word.feature[2] in ("数詞",) && continue
            push!(sentence, w)
        end
        #println(sentence)
        resultarray[i] = sentence
    end
    return resultarray
end

function lexrank(sentences, threshold, mmr_l)
    
    word2indexhash = Dict{String, Int}()
    let index = 1
        for s in sentences, word in s
            haskey(word2indexhash, word) && continue
            push!(word2indexhash, word=>index)
            index += 1
        end
    end
    #println(word2indexhash)
    
    idfarray = idf(sentences, word2indexhash)
    tfidfarrays = Tuple(tf(s, word2indexhash) .* idfarray for s in sentences)
    
    sentencescout = length(sentences)
    #println(tfidfarrays)
    matrix = fill(1//1, (sentencescout, sentencescout))
    rawscoresmatrix = fill(0.0, (sentencescout, sentencescout))
    for (row, tfidfarray1) in enumerate(tfidfarrays)
        degree = 0
        for (col, tfidfarray2) in enumerate(tfidfarrays)
            simi = cosine_sim(tfidfarray1, tfidfarray2)
            if simi == NaN
                simi = 0.0
                println(sentences[row], sentences[col])
            end
            try
                rawscoresmatrix[row, col] = simi
            catch InexactError
                println(row,col, simi)
            end
            val = (simi>threshold) ? 1 : 0
            matrix[row, col] = val
            degree += val
        end
        #println(degree)
        degree == 0 && continue
        matrix[row, :] .//= degree
    end
    #println(matrix)
    
    scores = powermethod(matrix)
    
    
    rated = Vector{Tuple{Int, Float64}}()
    selectedindex = Set{Int}()
    for _ in 1:sentencescout
        max_index = 1
        max_score = - Inf64 
        for i in 1:sentencescout
            i in selectedindex && continue
            basescore = scores[i]
            if isempty(selectedindex)
                max_simi = 0
            else
                max_simi = maximum(rawscoresmatrix[i, j] for j in selectedindex)/10.0
            end
            val = mmr_l * basescore - (1 - mmr_l) * max_simi
            if val > max_score
                max_score = val
                max_index = i
            end
        end
        push!(rated, (max_index, max_score))
        push!(selectedindex, max_index)
    end

    return rated
    
end

function idf(sentences, word2vechash)::Vector{Float64}
    sentencescount = length(sentences)
    idfarray = fill(0.0, length(word2vechash))
    for (word,index) in word2vechash
        count = sum(1 for s in sentences if word in s)
        count == 0 && continue
        idfarray[index] += (log(sentencescount/count)+0.0) #ここに+1をつけている実装が多いが詳細不明
    end
    return idfarray
end


function tf(sentence, word2vechash)::Vector{Float64}
    wordscount = length(word2vechash)
    tfarray = fill(0.0, wordscount)
    totalwords = length(sentence)
    
    for word in sentence
        tfarray[word2vechash[word]] += 1#/totalwords #ここの分母が文中の最大カウントの実装が多い。同じく詳細不明
    end
    
    #=
    tfarray ./= maximum(tfarray)
    =#
    return tfarray
end
return tf

function cosine_sim(veca, vecb)::Float64
    dot(veca, vecb)/(norm(veca)*norm(vecb))
end

function powermethod(a::Matrix; eps = 1e-8)
    p = fill(1/size(a, 1), size(a,1))
    delta = 1.0
    while  delta > eps
        p1 = a'p
        delta = norm(p1-p)
        p = p1
    end
    return p
end
