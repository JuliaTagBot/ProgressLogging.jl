module ProgressLogging

using Logging, Printf
import Logging: handle_message, shouldlog, min_enabled_level
export ProgressLogger, BarGlyphs, with_progress, @progress

include("BarGlyphs.jl")
include("utils.jl")

mutable struct ProgressLogger <: AbstractLogger
	parent_logger::AbstractLogger
	output::IO

	percentage::Real
	
	tfirst::Float64
	tlast::Float64
	dt::Float64

	printed::Bool

	desc::AbstractString
	barlen::Int
	barglyphs::BarGlyphs
	desc_color::Symbol
	bar_color::Symbol

	numprintedvalues::Int
	current_values::Vector{Any}

	function ProgressLogger(; dt=0.1, desc="Progress: ", desc_color=:green,
							bar_color=:color_normal, output=stderr,
							barlen=tty_width(desc),
							barglyphs=BarGlyphs('|','█','█',' ','|'))
		percentage = 0.
		tfirst = tlast = time()
		printed = false
		numprintedvalues = 0

		new(current_logger(), output, percentage, tfirst, tlast, dt, printed,
			desc, barlen, barglyphs, desc_color, bar_color, numprintedvalues, Any[])
	end
end

function handle_message(logger::ProgressLogger, level, message, mod, group, id,
						file, line; kwargs...)
	if haskey(kwargs, :_progress)

		logger.percentage = kwargs[:_progress]

		time() < logger.tlast + logger.dt && return

		current_values = Any[]
		for (key, value) in kwargs
			key_str = string(key)
			key_str[1] != '_' && push!(current_values, (key_str, value))
		end
		logger.current_values = current_values

		logger.printed && move_cursor_up_while_clearing_lines(logger.output, logger.numprintedvalues)
		print_progress(logger)
	else
		logger.printed && move_cursor_up_while_clearing_lines(logger.output, logger.numprintedvalues)
		logger.printed && print("\r\u1b[K")
		with_logger(logger.parent_logger) do 
			@logmsg(level, message, _module=mod, _group=group, _id=id,
			_file=file, _line=line, kwargs...)
		end
		print_progress(logger)
		# logger.numprintedvalues > 0 && println(logger.output)
	end
end
function shouldlog(logger::ProgressLogger, args...)
	shouldlog(logger.parent_logger, args...)
end
min_enabled_level(logger::ProgressLogger) = min_enabled_level(logger.parent_logger)

function print_progress(p::ProgressLogger)
    t = time()

    p.percentage > 100 && return

    bar = barstring(p.barlen, p.percentage, barglyphs=p.barglyphs)
    elapsed_time = t - p.tfirst
    est_total_time = 100 * elapsed_time / p.percentage
    if 0 <= est_total_time <= typemax(Int)
        eta_sec = round(Int, est_total_time - elapsed_time )
        eta = durationstring(eta_sec)
    else
        eta = "N/A"
    end
	bar_str = @sprintf "%3u%%%s  ETA: %s" round(Int, p.percentage) bar eta

    prefix = length(p.current_values) == 0 ? "[ " : "┌ "
    printover(p.output, prefix*p.desc, bar_str, p.desc_color, p.bar_color)
    printvalues!(p, p.current_values; prefix_color=p.desc_color, value_color=p.bar_color)

    # Compensate for any overhead of printing. This can be
    # especially important if you're running over a slow network
    # connection.
    p.tlast = t + 2*(time()-t)
    p.printed = true

    return nothing
end

function finish_progress(p::ProgressLogger)
	!p.printed && return

    bar = barstring(p.barlen, 100, barglyphs=p.barglyphs)
	dur = durationstring(time()-p.tfirst)
    bar_str = @sprintf "100%%%s Time: %s" bar dur
    prefix = length(p.current_values) == 0 ? "[ " : "┌ "

	move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
    printover(p.output, prefix*p.desc, bar_str, p.desc_color, p.bar_color)
    printvalues!(p, p.current_values; prefix_color=p.desc_color, value_color=p.bar_color)
    println(p.output)
end

# Internal method to print additional values below progress bar
function printvalues!(p::ProgressLogger, showvalues; prefix_color=false, value_color=false)
    len = length(showvalues)
    len == 0 && return

    maxwidth = maximum(Int[length(string(name)) for (name, _) in showvalues])

    for (i, (name, value)) in enumerate(showvalues)
    	prefix = i == len ? "\n└   " : "\n│   "
        msg = rpad(string(name) * ": ", maxwidth+2+1) * string(value)

 		(prefix_color == false) ? print(p.output, prefix) : printstyled(p.output, prefix; color=prefix_color, bold=true)
 		(value_color == false) ? print(p.output, msg) : printstyled(p.output, msg; color=value_color)
    end
    p.numprintedvalues = length(showvalues)
end

function with_progress(f::Function; kwargs...)
	logger = ProgressLogger(; kwargs...)
	with_logger(logger) do
		f()
	end
	finish_progress(logger)
end

macro progress(percentage)
	:(@info("", _progress=$(esc(percentage)), _module=nothing, _group=nothing, _id=nothing, _file=nothing, _line=nothing))
end

end # module