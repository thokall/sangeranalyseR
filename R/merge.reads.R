#' Merge fwd and reverse reads into a single sequence
#' 
#' This function attempts to merge any number of forward and reverse sequences into a single consensus sequence. It calculates a number of statistics that should help you decide whether a sensible consensus sequence exists for your data.\cr
#' Note that sequence names can be provided via the names on the input lists. If this is done, the names will be preserved in the output data. Otherwise, sequences will be called: fwd_1, fwd_2, etc.
#'
#' @param fwd.seqs a list of forward sequences, each should be a sangerseq s4 object from the sangerseqR package. These sequences will not be reverse-complemented before alignment.
#' @param rev.seqs a list of reverse sequences, each should be a sangerseq s4 object from the sangerseqR package. These sequences will be reverse-complemented before alignment.
#' @param ref.aa.seq an amino acid reference sequence supplied as a string or an AAString object. If your sequences are protein-coding DNA seuqences, and you want to have frameshifts automatically detected and corrected, supply a reference amino acid sequence via this argument. If this argument is supplied, the sequences are then kept in frame for the alignment step. Fwd sequences are assumed to come from the sense (i.e. coding, or "+") strand.
#' @param minInformation minimum fraction of the sequences required to call a consensus sequence at any given position (see the ConsensusSequence() function from DECIPHER for more information). Defaults to 1.0 for this function, implying that the consensus sequence is only called when all fwd and rev reads overlap.
#' @param minReads minimum number of reads that are required to call a consensus sequence at any given position. This can be used in place of minInformation if you set minInformation to 0.0. For example, if you expect to have non-overlapping reads making up your consensus, but only wish to call a consensus where at least two reads overlap, set minInformation to 0.0 and minReads to 2. If you set both minInformation and minReads, the value corresponding to the larger number of reads will be used.
#' @param processors The number of processors to use, or NULL (the default) for all available processors
#' @param genetic.code Named character vector in the same format as GENETIC_CODE (the default), which represents the standard genetic code. This is the code with which the function will attempt to translate your DNA sequences. You can get an appropriate vector with the getGeneticCode() function. The default is the standard code.
#' 
#' @return a list with the following components:
#'          \enumerate{
#'              \item consensus: the consensus sequence from the merged reads.\cr
#'              \item alignment: the alignment of all the reads, with the called consensus sequence. E.g. if the list was called 'merged.reads', you could use BrowseSeqs(merged.reads$alignment) to view the alignment.
#'              \item differences: a data frame of the number of pairwise differences between each read and the consensus sequence, as well as the number of bases in each input read that did not contribute to the consensus sequence. Can assist in detecting incorrect reads, or reads with a lot of errors.
#'              \item distance.matrix: a distance matrix of genetic distances (corrected with the JC model) between all of the input reads.
#'              \item dendrogram: a dendrogram depicting the distance.matrix. E.g. if the list was called 'merged.reads', you could use plot(merged.reads$dendrogram) to see the dendrogram.
#'              \item indels: if you specified a reference sequence via ref.aa.seq, then this will be a data frame describing the number of indels and deletions that were made to each of the input reads in order to correct frameshift mutations.
#'          }
#'
#' @keywords merge, reads, alignment, sequence
#'
#' @export merge.reads
#'

merge.reads <- function(fwd.seqs, rev.seqs, ref.aa.seq = NULL, minInformation = 1.0, minReads = 0, processors = NULL, genetic.code = GENETIC_CODE){

    if(minReads > n.reads){ stop("minReads must be less than or equal to the number of reads you have")}

    if(is.null(processors)) { processors = detectCores(all.tests = FALSE, logical = FALSE)}

    if(is.null(names(fwd.seqs))){
        names(fwd.seqs) = paste("fwd", 1:length(fwd), sep = "_")
    }

    if(is.null(names(rev.seqs))){
        names(rev.seqs) = paste("rev", 1:length(rev), sep = "_")
    }

    # Reverse complement reverse reads, and join into DNAStringSet
    print("Reverse compelementing reverse reads")
    fwd = mclapply(fwd.seqs, get.primaryseq.xstring, revcomp = FALSE, mc.cores = processors) 
    rev = mclapply(rev.seqs, get.primaryseq.xstring, revcomp = TRUE, mc.cores = processors) 
    seqs = DNAStringSet(c(fwd, rev))


    # Try to correct framshifts in the input sequences 
    if(!is.null(ref.aa.seq)) {
        print("Correcting frameshifts in reads using amino acid reference sequence")
        corrected = CorrectFrameshifts(myXStringSet = seqs, myAAStringSet = AAStringSet(ref.aa.seq), geneticCode = genetic.code, type = 'both', processors = processors, verbose = FALSE)
        seqs = corrected$sequences
        indels = get.indel.df(corrected$indels)        
    }else{
        indels = NULL
    }


    # align the sequences
    print("Aligning reads")
    if(!is.null(ref.aa.seq)){
        aln = AlignTranslation(seqs, geneticCode = genetic.code, processors = processors, verbose = FALSE)
    }else{
        aln = AlignSeqs(seqs, processors = processors, verbose = FALSE)
    }
    names(aln) = c(names(fwd.seqs), names(rev.seqs))

    # call consensus
    print("Calling consensus sequence")
    n.reads = length(seqs)
    implied.minInfo = minReads/n.reads
    minInformation = max(c(minInformation, implied.minInfo))
    consensus = ConsensusSequence(aln,
                                  minInformation = minInformation,
                                  includeTerminalGaps = TRUE,
                                  noConsensusChar = "-")[[1]]


    print("Calculting differences between reads and consensus")
    diffs = mclapply(aln, n.pairwise.diffs, subject = consensus, mc.cores = processors)
    diffs = do.call(rbind, diffs)
    diffs.df = data.frame("name" = names(aln), "pairwise.diffs.to.consensus" = diffs[,1], "unused.chars" = diffs[,2])
    rownames(diffs.df) = NULL

    # get a dendrogram
    dist = DistanceMatrix(aln, correction = "Jukes-Cantor", penalizeGapLetterMatches = FALSE, processors = processors, verbose = FALSE)
    dend = IdClusters(dist, asDendrogram = TRUE, processors = processors, verbose = FALSE)

    # add consensus to alignment
    aln2 = c(aln, DNAStringSet(consensus))
    names(aln2)[length(aln2)] = "consensus"

    # strip gaps from consensus (must be an easier way!!)
    consensus.gapfree = DNAString(paste(del.gaps(consensus), collapse = ''))

    return(list("consensus" = consensus.gapfree, 
                "alignment" = aln2, 
                "differences" = diffs.df, 
                "distance.matrix" = dist,
                "dendrogram" = dend,
                "indels" = indels)) 
}

get.primaryseq.xstring <- function(seq, revcomp){

    if(revcomp == FALSE){
        return(seq@primarySeq)
    }else{
        return(reverseComplement(seq@primarySeq))
    }

} 

get.indel.df <- function(indel.list){

    r = lapply(indel.list, indel.row)
    indel.df = data.frame(matrix(unlist(r), byrow = T, nrow = length(indel.list)))
    indel.df = cbind(names(indel.list), indel.df)
    names(indel.df) = c('read', 'insertions', 'deletions', 'distance')    
    return(indel.df)

}

indel.row <- function(row){

    n.ins = length(row$insertions)
    n.del = length(row$deletions)
    dist = row$distance
    return(c(n.ins, n.del, dist))
}

n.pairwise.diffs <- function(pattern, subject){
    # pairwise differences assuming pattern and subject are aligned
    comp = compareStrings(pattern, subject)
    qs = str_count(comp, '\\?')
    ps = str_count(comp, '\\+')
    return(c(qs, ps))
}