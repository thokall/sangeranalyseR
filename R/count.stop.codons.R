#' Count stop codons in a DNA sequence
#'
#' @param sequence a DNAString object
#' @param reading.frame a number from 1 to 3 denoting the reading frame of the sequence
#' @param genetic.code Named character vector in the same format as GENETIC_CODE (the default), which represents the standard genetic code. This is the code with which the function will attempt to translate your DNA sequences. You can get an appropriate vector with the getGeneticCode() function. The default is the standard code.
#'
#' @export count.stop.codons
#'

count.stop.codons <- function(sequence, reading.frame = 1, genetic.code = GENETIC_CODE){

    if(!reading.frame %in% c(1,2,3)){ stop("reading.frame must be 1, 2, or 3")}
    if(class(sequence)!='DNAString'){ stop("sequence must be a DNAString object")}
    if(!("*" %in% genetic.code)) { stop("Your genetic code does not specify any stop codons")}

    l = length(sequence) + 1 - reading.frame

    if(l < 3){
        warning(sprintf("Cannot calculate stop codons on sequence of length %d in reading frame %d", 
                        length(sequence), reading.frame))
        return(NULL)
    }

    # this comes almost straight from the BioStrings manual
    tri = trinucleotideFrequency(sequence[reading.frame:length(sequence)], step=3)

    names(tri) <- genetic.code[names(tri)]

    freqs = sapply(split(tri, names(tri)), sum)

    stops = freqs["*"]

    return(as.numeric(stops))
}
