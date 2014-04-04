makessp <-
  function(formula,data,type=NULL,nknots=NULL,rparm=NA,lambdas=NULL,
           skip.iter=TRUE,se.fit=FALSE,rseed=1234,gcvopts=NULL){
    ###### Makes Smoothing Splines with Parametric effects
    ###### Nathaniel E. Helwig (nhelwig2@illinois.edu)
    ###### Last modified: March 21, 2014
    
    ### get initial info 
    mf=match.call()
    m=match(c("formula","data"),names(mf),0L)
    mf=mf[c(1L, m)]
    mf[[1L]] = as.name("model.frame")
    mf=eval(mf, parent.frame())          # mf contains response and predictor info
    mt=attr(mf, "terms")                 # mt contains model info and terms 
    et=attr(mt,"factors")                # et is effects table
    mfdim=dim(et)                        # dim of effects table
    ndpts=dim(mf)[1]                     # total number of data points
    nxvar=mfdim[1]-1L                    # number of predictors
    nterm=mfdim[2]                       # number of model terms
    xynames=row.names(et)
    xnames=xynames[2:(nxvar+1L)]
    tnames=colnames(et)
    if(any(colSums(et>0L)>3L)){stop("Four-way (and higher-order) interactions are not supported.")}
    
    ### check response
    yvar=as.matrix(model.response(mf, "numeric")+0.0)   # response variable
    if(ncol(yvar)>1){stop("Response must be unidimensional (vector).")}
    if(nrow(yvar)!=ndpts){stop("Response vector must have same length as predictors.")}
    ysm=sum(yvar);  nunewr=ndpts;  fweights=rep.int(1L,ndpts);  yty=crossprod(yvar)
    
    ### check order of things for nonparametric predictors
    if(nxvar>1){
      snidx=match(xnames,names(type))
      if(any(is.na(snidx))){stop('Variable names in "type" must match variable names in "formula".')}
      type=type[snidx]
      if(is.na(rparm[1])==FALSE){
        rnidx=match(xnames,names(rparm))
        if(any(is.na(rnidx))){stop('Variable names in "rparm" must match variable names in "formula".')}
        rparm=rparm[rnidx]
      }
    } else{
      type=type[[1]]
      rparm=rparm[[1]]
    }
    if(sum(type=="prm")==nxvar){stop("Must include at least one nonparametric term in formula.")}
    
    ### collect predictors
    xvars=vector("list",nxvar)
    for(jj in 1:nxvar){xvars[[jj]]=mf[,jj+1L]}
    rm(mf)
    names(xvars)=xnames
    
    ### check predictor types
    flvls=xrng=vector("list",nxvar)
    xdim=vector("integer",nxvar)
    for(k in 1:nxvar){
      if(any(type[[k]]==c("cub","cub0","per","tps","prm"))){
        xvars[[k]]=as.matrix(xvars[[k]]+0.0)
        xdim[k]=ncol(xvars[[k]])
        if(type[[k]]=="tps"){
          if(xdim[k]>3){stop(paste("Too many predictors for",xnames[k]))}
        } else{
          if(xdim[k]>1){stop(paste("Too many predictors for",xnames[k]))}
        }
        if(is.na(rparm[1])==FALSE){xrng[[k]]=apply(xvars[[k]],2,range)}
        flvls[[k]]=NA
      } else if (type[[k]]=="nom"){
        xvars[[k]]=as.factor(xvars[[k]])
        flvls[[k]]=levels(xvars[[k]])
        xvars[[k]]=matrix(as.integer(xvars[[k]]))
        xrng[[k]]=matrix(c(1,length(flvls[[k]])),2,1)
        xdim[k]=1L
      } else{
        stop('You must set type to either "cub", "cub0", "nom", "per", "tps", or "prm" for each effect in formula.')
      }
    } # end for(k in 1:nxvar)
    
    ### check knots and random seed
    if(is.null(nknots)){
      if(nxvar==1L){
        if(xdim[1]==1L){nknots=30} else if(xdim[1]==2L){nknots=100} else {nknots=200}
      } else if(nxvar==2L) {
        if(any(xdim>1)){nknots=200} else {nknots=100}
      } else {nknots=300} # end if(nxvar==1L)
    }
    if(is.null(rseed)==FALSE && length(nknots)==1L){set.seed(rseed)}
    theknots=vector("list",nxvar)
    if(length(nknots)>1){
      kidx=as.integer(nknots)
      nknots=length(kidx)
      if(any(kidx<1L) || any(kidx>nunewr)){stop("Input 'nknots' out of data index range.")}
    } else {kidx=NA}
    
    ### check for rounding
    if(is.na(rparm[1])){
      for(k in 1:nxvar){
        if(any(type[[k]]==c("cub","cub0","per"))){
          xrng[[k]]=range(xvars[[k]])
          xvars[[k]]=(xvars[[k]]-xrng[[k]][1])/(xrng[[k]][2]-xrng[[k]][1])
        }
        if(length(kidx)>1){for(k in 1:nxvar){theknots[[k]]=as.matrix(xvars[[k]][kidx,])}}
      } # end for(k in 1:nxvar)
      xorig=yorig=NA
    } else{
      xorig=xvars
      yorig=yvar
      # get rounded point indices
      gvec=matrix(1,ndpts,1);     kconst=1
      for(k in 1:nxvar){
        if(type[[k]]=="nom"){
          gvec = gvec + kconst*(xvars[[k]]-1L)
          kconst = kconst*xrng[[k]][2]
        } else if(type[[k]]=="prm"){
          gvec = gvec + kconst*round((xvars[[k]]-xrng[[k]][1])/rparm[[k]])
          kconst = kconst*round(1+(xrng[[k]][2]-xrng[[k]][1])/rparm[[k]])
          xvars[[k]]=as.matrix(round(xvars[[k]]/rparm[[k]]))*rparm[[k]]
        } else if(type[[k]]=="tps"){
          if(length(rparm[[k]])!=xdim[k]){rparm[[k]]=rep(rparm[[k]][1],xdim[k])}
          for(j in 1:xdim[k]){
            gvec = gvec + kconst*round((xvars[[k]][,j]-xrng[[k]][1,j])/rparm[[k]][j])
            kconst = kconst*round(1+(xrng[[k]][2,j]-xrng[[k]][1,j])/rparm[[k]][j])
            xvars[[k]][,j]=as.matrix(round(xvars[[k]][,j]/rparm[[k]][j]))*rparm[[k]][j]
          }
        } else{
          gidx=round(((xvars[[k]]-xrng[[k]][1])/(xrng[[k]][2]-xrng[[k]][1]))/rparm[[k]])
          gvec = gvec + kconst*gidx
          kconst = kconst*round(1+1/rparm[[k]])
          xvars[[k]]=as.matrix(gidx*rparm[[k]]);  rm(gidx)
        }
      } # end for(k in 1:nxvar)
      # get unique points, frequencies, and sums
      gvec=as.integer(gvec)
      glindx=split(cbind(1:ndpts,yvar),gvec)
      if(is.na(kidx[1])==FALSE){for(k in 1:nxvar){theknots[[k]]=as.matrix(xvars[[k]][kidx,])}}
      fs=matrix(unlist(lapply(glindx,unifqsum)),ncol=3,byrow=TRUE)
      for(k in 1:nxvar){xvars[[k]]=as.matrix(xvars[[k]][fs[,1],])}
      yvar=fs[,2];  fweights=fs[,3];   nunewr=length(yvar)
    } # end if(is.na(rparm[1]))
    
    ### get knot indices
    if(length(kidx)==1L){
      nknots=as.integer(min(c(nunewr,nknots)))
      if(nknots<1){stop("Input 'nknots' must be positive integer.")}
      kidx=sample(nunewr,nknots,prob=(fweights/ndpts))
      for(k in 1:nxvar){theknots[[k]]=as.matrix(xvars[[k]][kidx,])}
    } 
    
    ### make marginal reproducing kernel matrices
    rks=makerkm(xvars,type,theknots,xrng)
    
    ### collect output
    ylist=list(yvar)
    names(ylist)=xynames[1]
    sspmk=list(et=et,n=c(nunewr,ndpts),xvars=c(xvars,ylist),nxvar=nxvar,yty=yty,
               fweights=fweights,type=type,xdim=xdim,theknots=theknots,nknots=nknots,
               lambdas=lambdas,rks=rks[1:4],gcvopts=gcvopts,xorig=xorig,yorig=yorig,
               se.fit=se.fit,skip.iter=skip.iter,ysm=ysm,rparm=rparm,xrng=xrng,
               flvls=flvls,tpsinfo=rks$tpsinfo,formula=formula)
    class(sspmk)<-"makessp"
    return(sspmk)
    
  }