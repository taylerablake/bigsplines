sspwork <-
  function(formula,sspmk){
    
    ### check inputs
    if(formula==sspmk$formula){
      Etab=sspmk$et
      mfdim=dim(Etab)
      tnames=colnames(Etab)
      oldnames=rownames(sspmk$et)[2:(sspmk$nxvar+1L)]
    } else{
      
      # get formula
      trmfrm=terms.formula(formula)
      ychk=attr(trmfrm,"response")
      if(ychk!=1L){stop("Must include same response in formula when entering 'makessa' object.")}
      et=attr(trmfrm,"factors");   mfdim=dim(et)
      newnames=rownames(et);       tnames=colnames(et)
      mtidx=match(tnames,colnames(sspmk$et))
      if(any(is.na(mtidx))){stop("Cannot add new effects to formula when entering 'makessa' object.")}
      oldnames=rownames(sspmk$et)
      if(newnames[1]!=oldnames[1]){stop("Must include same response in formula when entering 'makessa' object.")}
      newnames=newnames[2:mfdim[1]]
      oldnames=oldnames[2:(sspmk$nxvar+1L)]
      
      # check order of predictors
      midx=match(newnames,oldnames)
      if(any(is.na(midx))){stop("Cannot include new predictors in formula when entering 'makessa' object. \n Refit model using bigssp function.")}
      Etab=matrix(0L,sspmk$nxvar,mfdim[2])
      Etab[midx,]=et[-1,]
      rownames(Etab)=oldnames
      colnames(Etab)=tnames
      Etab=rbind(0L,Etab)
      
    } # end if(formula==sspmk$formula)
    
    ### get info
    xnames=oldnames;  tnames=tnames;  xdim=sspmk$xdim
    if(is.null(sspmk$gcvopts)){
      maxit=5;  gcvtol=10^-5;  alpha=1
    } else {maxit=sspmk$gcvopts$maxit;  gcvtol=sspmk$gcvopts$gcvtol;  alpha=sspmk$gcvopts$alpha}
    if(is.null(sspmk$lambdas)){lambdas=10^-(9:0)} else {lambdas=sspmk$lambdas}
    
    ### make design and penalty matrices
    dps=sspdpm(sspmk$xvars,sspmk$type,sspmk$rks,sspmk$theknots,Etab)
    Knames=colnames(dps$Kmat);   
    jdim=dim(dps$Jmats);    Jnames=colnames(dps$Jmat)[seq(1,jdim[2],by=sspmk$nknots)]
    
    ### get cross-product matrices
    wsqrt=sqrt(sspmk$fweights)
    KtJ=crossprod(dps$Kmat*sspmk$fweights,dps$Jmats)
    KtK=crossprod(dps$Kmat*wsqrt)
    JtJ=crossprod(dps$Jmats*wsqrt)
    Kty=crossprod(dps$Kmat,sspmk$xvars[[sspmk$nxvar+1]])
    Jty=crossprod(dps$Jmats,sspmk$xvars[[sspmk$nxvar+1]])
    
    ### initialize smoothing parameters
    nbf=length(Kty)
    if(ncol(dps$Qmats)>sspmk$nknots){
      thetas=smartssp(dps$Qmats,lambdas,Kty,Jty,KtK,KtJ,
                      JtJ,sspmk$nknots,sspmk$n[2],alpha,sspmk$yty,nbf)
    } else {thetas=1}
    
    ### estimate optimal smoothing parameters
    if(sspmk$skip.iter){
      cvg=NA
      fxhat=lamcoef(lambdas,thetas,Kty,Jty,KtK,KtJ,JtJ,
                    dps$Qmats,sspmk$nknots,sspmk$n[2],alpha,sspmk$yty,nbf)
      fhat=fxhat[[1]]
      dchat=fhat[1:(nbf+sspmk$nknots)]
      yhat=cbind(dps$Kmat,dps$Jmats%*%kronecker(thetas,diag(sspmk$nknots)))%*%dchat
      sseval=fhat[nbf+sspmk$nknots+1]
      effdf=fhat[nbf+sspmk$nknots+2]
      if(sseval<=0){
        if(is.na(sspmk$rparm[1])){sseval=sum((sspmk$xvars[[sspmk$nxvar+1]]-yhat)^2)} else{sseval=.Machine$double.eps}
        warning("Approximated SSE is less than 0, so model 'info' may be invalid. \nTry reducing the number of knots or increasing lambda range (e.g., lambdas=10^-(5:0)).")
      }
      if(effdf>=(sspmk$n[2]-1L)){
        effdf=sspmk$n[2]-.Machine$double.eps
        warning("Effective degrees of freedom exceeds n-1, so model 'info' may be invalid. \nTry reducing the number of knots or increasing lambda range (e.g., lambdas=10^-(5:0)).")
      }
      mevar=sseval/(sspmk$n[2]-effdf)
      gcv=sspmk$n[2]*sseval/((sspmk$n[2]-alpha*effdf)^2)
      newlam=lambdas[fhat[nbf+sspmk$nknots+3]]
      aic=sspmk$n[2]*(1+log(2*pi))+sspmk$n[2]*log(sseval/sspmk$n[2])+effdf*2
      bic=sspmk$n[2]*(1+log(2*pi))+sspmk$n[2]*log(sseval/sspmk$n[2])+effdf*log(sspmk$n[2])
      csqrt=sqrt(mevar)*fxhat[[2]]
      iter=vtol=NA
    } else {
      
      # iterate estimates of lambda and etas until convergence
      vtol=1;   gcv=sspmk$yty;   iter=0L;  cvg=FALSE
      while(vtol>gcvtol && iter<maxit && min(c(thetas,gcv))>0) {

        if(ncol(dps$Qmats)==sspmk$nknots){
          nqmat=matrix(0,nbf+sspmk$nknots,nbf+sspmk$nknots)
          nqmat[(nbf+1):(sspmk$nknots+nbf),(nbf+1):(sspmk$nknots+nbf)]=sspmk$n[2]*dps$Qmats
          if(length(lambdas)>1){
            newlam=lamloop(lambdas,thetas,Kty,Jty,KtK,KtJ,JtJ,
                           dps$Qmats,sspmk$nknots,sspmk$n[2],alpha,sspmk$yty,nbf)
          } else{newlam=lambdas}
          gcvopt=nlm(f=gcvcss,p=log(newlam),yty=sspmk$yty,
                     xtx=rbind(cbind(KtK,KtJ),cbind(t(KtJ),JtJ)),
                     xty=rbind(Kty,Jty),nqmat=nqmat,ndpts=sspmk$n[2],alpha=alpha)
          gcv=gcvopt$min;    newlam=exp(gcvopt$est)
          vtol=0
        } else{
          
          # step 1: find optimal lambda given thetas
          newlam=lamloop(lambdas,thetas,Kty,Jty,KtK,KtJ,JtJ,
                         dps$Qmats,sspmk$nknots,sspmk$n[2],alpha,sspmk$yty,nbf)
          
          # step 2: find optimal etas given lambda
          gcvopt=nlm(f=gcvssp,p=log(thetas),yty=sspmk$yty,KtK=KtK,KtJ=KtJ,Kty=Kty,
                     Jty=Jty,JtJ=JtJ,Qmats=dps$Qmats,ndpts=sspmk$n[2],alpha=alpha,
                     nknots=sspmk$nknots,newlam=newlam,nbf=nbf)
          newgcv=gcvopt$min
          
          # step 3: check for convergence
          thetas=exp(gcvopt$est)
          vtol=(gcv-newgcv)/gcv
          gcv=newgcv
          iter=iter+1
          
        } # end if(ncol(dps$Qmats)==sspmk$nknots)
      } # end while(vtol>gcvtol && iter<maxit && min(thetas)>0)
      
      # get final estimates
      fxhat=lamcoef(newlam,thetas,Kty,Jty,KtK,KtJ,JtJ,
                    dps$Qmats,sspmk$nknots,sspmk$n[2],alpha,sspmk$yty,nbf)
      fhat=fxhat[[1]]
      dchat=fhat[1:(nbf+sspmk$nknots)]
      yhat=cbind(dps$Kmat,dps$Jmats%*%kronecker(thetas,diag(sspmk$nknots)))%*%dchat
      sseval=fhat[nbf+sspmk$nknots+1]
      effdf=fhat[nbf+sspmk$nknots+2]
      if(sseval<=0){
        if(is.na(sspmk$rparm[1])){sseval=sum((sspmk$xvars[[sspmk$nxvar+1]]-yhat)^2)} else{sseval=.Machine$double.eps}
        warning("Approximated SSE is less than 0, so model 'info' may be invalid. \nTry reducing the number of knots or increasing lambda range (e.g., lambdas=10^-(5:0)).")
      }
      if(effdf>=(sspmk$n[2]-1L)){
        effdf=sspmk$n[2]-.Machine$double.eps
        warning("Effective degrees of freedom exceeds n-1, so model 'info' may be invalid. \nTry reducing the number of knots or increasing lambda range (e.g., lambdas=10^-(5:0)).")
      }
      mevar=sseval/(sspmk$n[2]-effdf)
      gcv=sspmk$n[2]*sseval/((sspmk$n[2]-alpha*effdf)^2)
      aic=sspmk$n[2]*(1+log(2*pi))+sspmk$n[2]*log(sseval/sspmk$n[2])+effdf*2
      bic=sspmk$n[2]*(1+log(2*pi))+sspmk$n[2]*log(sseval/sspmk$n[2])+effdf*log(sspmk$n[2])
      csqrt=sqrt(mevar)*fxhat[[2]]
      
    } # end if(sspmk$skip.iter)
    
    ### posterior variance
    pse=NA
    if(sspmk$se.fit){pse=sqrt(postvar(dps$Kmat,dps$Jmats%*%kronecker(thetas,diag(sspmk$nknots)),csqrt))}
    
    ### calculate vaf
    mval=sspmk$ysm/sspmk$n[2]
    vaf=1-sseval/(sspmk$yty-sspmk$n[2]*(mval^2))
    
    ### retransform predictors
    for(k in 1:sspmk$nxvar){
      if(any(sspmk$type[[k]]==c("cub","acub","per"))){
        sspmk$xvars[[k]]=as.matrix(sspmk$xvars[[k]]*(sspmk$xrng[[k]][2]-sspmk$xrng[[k]][1])+sspmk$xrng[[k]][1])
      } else if(sspmk$type[[k]]=="nom"){
        sspmk$xvars[[k]]=as.matrix(sspmk$flvls[[k]][sspmk$xvars[[k]]])
        if(is.na(sspmk$rparm[1])==FALSE){sspmk$xorig[[k]]=as.matrix(sspmk$flvls[[k]][sspmk$xorig[[k]]])}
      }
    } # end for(k in 1:sspmk$nxvar)
    if(is.na(sspmk$rparm[1])==FALSE){
      yunique=sspmk$xvars[[sspmk$nxvar+1]]/as.numeric(sspmk$fweight); yvar=sspmk$yorig
      xunique=sspmk$xvars[1:sspmk$nxvar];  sspmk$xvars=sspmk$xorig
    } else{xunique=yunique=NA;  yvar=sspmk$xvars[[sspmk$nxvar+1]]; sspmk$xvars=sspmk$xvars[1:sspmk$nxvar]}
    
    ### collect results
    names(thetas)=Jnames
    if(sspmk$skip.iter==FALSE && vtol<=gcvtol){cvg=TRUE}
    ndf=data.frame(n=sspmk$n[2],df=effdf,row.names="")
    modelspec=list(myknots=sspmk$theknots,rparm=sspmk$rparm,lambda=newlam,
                   thetas=thetas,gcvopts=sspmk$gcvopts,nxvar=xdim,xrng=sspmk$xrng,
                   flvls=sspmk$flvls,tpsinfo=sspmk$tpsinfo,iter=iter,vtol=vtol,
                   coef=dchat,coef.csqrt=csqrt,Etab=Etab,Knames=Knames)
    sspfit=list(fitted.values=yhat,se.fit=pse,yvar=yvar,xvars=sspmk$xvars,
                type=sspmk$type,yunique=yunique,xunique=xunique,sigma=sqrt(mevar),
                ndf=ndf,info=c(gcv=gcv,rsq=vaf,aic=aic,bic=bic),modelspec=modelspec,
                converged=cvg,tnames=tnames)
    return(sspfit)
    
  }