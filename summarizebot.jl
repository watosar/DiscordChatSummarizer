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
    
    args = Dict(split(i, ":") for i in split(m.content, " ")[2:end])
    bef, aft = parse(Int, args["bef"]), parse(Int, args["aft"])
    num = parse(Int, get(args, "num", "3"))
    threshold = parse(Float64, get(args, "threshold", "0.1"))
    mmr = parse(Float64, get(args, "mmr", "0.8"))
    igpref = parse(Float64, get(args, "igpref", "2")) * 2
    println("bef:$(bef), aft:$aft, num:$num, threshold:$threshold, mmr:$mmr")
    doc = ""
    resp = get_channel_history(
        c, m.channel_id, before=bef, after=aft, limit=-1
    )
    
    for _m in resp
        messagepref = "$(_m.id):$(_m.author.id)"
        
        content = _m.content
        content == "" && continue
        content = replace(
            content,
            r"\n[ \n]+" => "\n"
        )
        content = replace(
            content,
            r"。(?!=[ ]*\n)" => "。$messagepref "
        )
        content = replace(
            content,
            r"\n(?=[ ]*[^ \n]+)" => "\n$messagepref "
        )

        doc *= "$messagepref $content\n"
    end
    # println(doc)
    baseurl = "https://discord.com/channels/$(m.guild_id)/$(m.channel_id)/"
    sumtuple = Tuple(Iterators.take(Summarize(
        doc, threshold=threshold, mmr_l=mmr, igpref=igpref), num))
    println(sumtuple)
    sumdoc = """summarized $(length(resp)) messages
        from:$(baseurl)$(resp[1].id) to:$(baseurl)$(resp[end].id)
        """ * join([
        begin    
            pref, content = split(t[2], " ", limit=2)
            """ $(baseurl)$(split(pref, ":")[1])
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
        pattarn=r"^bef:(.+) aft:(.+)( [a-zA-Z]+:[0-9.]+)$"
    )
    # Wait for the client to disconnect.
    return c
end

end

client = Bot.main()
wait(client)
