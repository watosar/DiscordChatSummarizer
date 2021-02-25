module Lexrank
include("./lexrank.jl")
end

module Bot

using Discord
using ..Lexrank:Summarize

function onready(c::Client, e::Ready)
    println("on ready")
end

function get_channel_history(c, channel_id; before=0, after=0, limit=50)
    messags = Vector{Message}()
    if limit == -1
        limit = 10000
    end
    resp::Vector{Message} = []
    for _ in 1:div(limit, 100)
        for m in fetchval(get_channel_messages(
            c, channel_id, before=before, limit=100
        ))
            if m.id == after
                limit = 0
                break
            end
            push!(resp, m)
            before = m.id
        end
        if limit == 0
            break
        end
    end
    if limit % 100 !== 0
        for m in fetchval(get_channel_messages(
            c, m.channel_id, 
            before=before, limit=limit % 100
        ))
            if m.id == after
                limit = 0
                break
            end
            push!(resp, m)
        end
    end

    return resp
end

function summarize(c::Client, m::Message)
    # Display the message contents.
    println("Received message: $(m.content)")
    
    coms = split(m.content, " ")
    bef, aft = coms[2:3]
    num = parse(Int, get(coms, 4, "num:3")[5:end])
    threshold = parse(Float64, get(coms, 5, "threshold:0.1")[11:end])
    mmr_l = parse(Float64, get(coms, 6, "mmr_l:0.8")[7:end])
    # _, bef = split(m.content, " ")
    doc = ""
    resp = get_channel_history(
        c, m.channel_id, 
        before=parse(Int, bef[5:end]), after=parse(Int, aft[5:end]),
        limit=-1
    )
    
    for _m in resp
        _mid = string(_m.id)
        content = _m.content
        content == "" && continue
        content = replace(
            content,
            r"\n[ \n]+" => "\n"
        )
        content = replace(
            content,
            r"。(?!=[ ]*\n)" => "。$(_mid) "
        )
        content = replace(
            content,
            r"\n(?=[ ]*[^ \n]+)" => "\n$(_mid) "
        )

        doc *= "$(_mid) $content\n"
    end
    # println(doc)
    baseurl = "https://discord.com/channels/$(m.guild_id)/$(m.channel_id)/"
    sumtuple = Tuple(Iterators.take(Summarize(
        doc, threshold=threshold, mmr_l=mmr_l), 3))
    println(sumtuple)
    sumdoc = """summarized $(length(resp)) messages
        from:$(baseurl)$(resp[1].id) to:$(baseurl)$(resp[end].id)
        """ * join([
        begin    
            mid, content = split(t[2], " ", limit=2)
            """ $(baseurl)$(mid)
            > $(content)"""
        end for t in sumtuple
    ], "\n")
    reply(c, m, sumdoc)
end

function main()
    # Create a client.
    c = Client(
        ENV["token"]; 
        prefix="/",
        presence=(game = (name = "with Discord.jl", type = AT_GAME),)
    )
    
    # Log in to the Discord gateway.
    println("open")
    open(c)

    # Add the handler.
    add_handler!(c, Ready, onready)
    add_command!(
        c, :summa, summarize;
        pattarn=r"^summa bef:(.+) aft:(.+)( num:(.+)?( threshold:(.+)( mmr_l:(.+))?)?)?"
    )
    # Wait for the client to disconnect.
    return c
end

end

client = Bot.main()
wait(client)
