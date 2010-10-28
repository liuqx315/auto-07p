!-----------------------------------------------------------------------
!-----------------------------------------------------------------------
!        Subroutines for the Continuation of general algebraic equations
!        (incl. BPs and Folds)
!-----------------------------------------------------------------------
!-----------------------------------------------------------------------
MODULE TOOLBOXAE

  USE AUTO_CONSTANTS, ONLY : AUTOPARAMETERS
  USE AE
  USE INTERFACES

  IMPLICIT NONE
  PRIVATE

  PUBLIC :: AUTOAEP,INITAE,STPNAE,FNCSAE,FNCSAEF,FNBTAE
  PUBLIC :: FNLP,FNLPF,STPNLP,STPNLPF ! Folds (Algebraic Problems)
  PUBLIC :: FNBP,FNBPF,STPNBP,STPNBPF ! Branch points

  DOUBLE PRECISION, PARAMETER :: HMACH=1.0d-7

CONTAINS

! ---------- ------
  SUBROUTINE INITAE(AP)

    TYPE(AUTOPARAMETERS), INTENT(INOUT) :: AP

    INTEGER NDIM, NFPR

    NDIM = AP%NDIM
    NFPR = 1
    SELECT CASE(AP%ITPST)
    CASE(1)
       ! ** BP cont (Algebraic Problems) (by F. Dercole)
       NDIM=2*NDIM+2
       NFPR=ABS(AP%ISW)
    CASE(2)
       ! ** Fold
       NDIM=2*NDIM+1
       NFPR=2
    END SELECT
    AP%NDIM = NDIM
    AP%NFPR = NFPR

  END SUBROUTINE INITAE

! ---------- -------
  SUBROUTINE AUTOAEP(AP,ICP,ICU)

    TYPE(AUTOPARAMETERS), INTENT(INOUT) :: AP
    INTEGER, INTENT(INOUT) :: ICP(:)
    INTEGER, INTENT(IN) :: ICU(:)

    CALL INITAE(AP)

    SELECT CASE(AP%ITPST)
    CASE(0)
       ! Algebraic systems.
       CALL AUTOAE(AP,ICP,ICU,FUNI,STPNAE,FNCSAE)
    CASE(1)
       ! ** BP cont (algebraic problems) (by F. Dercole).
       CALL AUTOAE(AP,ICP,ICU,FNBP,STPNBP,FNCSAE)
    CASE(2)
       ! ** Fold continuation (algebraic problems).
       CALL AUTOAE(AP,ICP,ICU,FNLP,STPNLP,FNCSAE)
    END SELECT
  END SUBROUTINE AUTOAEP

! ---------- ------
  SUBROUTINE STPNUS(AP,PAR,U,UDOT,NODIR)

! Gets the starting data from user supplied STPNT

    USE AUTO_CONSTANTS, ONLY : UVALS, PARVALS, unames, parnames
    USE SUPPORT, ONLY: NAMEIDX
    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(OUT) :: NODIR
    DOUBLE PRECISION, INTENT(OUT) :: U(*),UDOT(*),PAR(*)

    INTEGER NDIM,I
    DOUBLE PRECISION T

    NDIM=AP%NDIM
    T=0.d0
    U(:NDIM)=0.d0

    CALL STPNT(NDIM,U,PAR,T)

! override parameter/point values with values from constants file

    DO I=1,SIZE(UVALS)
       U(NAMEIDX(UVALS(I)%INDEX,unames))=UVALS(I)%VAR
    ENDDO
    DO I=1,SIZE(PARVALS)
       PAR(NAMEIDX(PARVALS(I)%INDEX,parnames))=PARVALS(I)%VAR
    ENDDO

    UDOT(1)=0
    NODIR=1
    
  END SUBROUTINE STPNUS

! ---------- ------
  SUBROUTINE STPNAE(AP,PAR,ICP,U,UDOT,NODIR)

    USE IO

    ! Gets the starting data from unit 3
    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*)
    INTEGER, INTENT(OUT) :: NODIR
    DOUBLE PRECISION, INTENT(OUT) :: U(*),UDOT(*),PAR(*)

    INTEGER NFPR,NFPRS,I
    INTEGER,ALLOCATABLE :: ICPRS(:)

    IF(AP%IRS==0)THEN
       CALL STPNUS(AP,PAR,U,UDOT,NODIR)
       RETURN
    ENDIF

    NFPRS=GETNFPR3()
    ALLOCATE(ICPRS(NFPRS))
    ICPRS(:)=0
    CALL READLB(AP,ICPRS,U,UDOT,PAR)
  
    ! Take care of the case where the free parameters have been changed at
    ! the restart point.

    NODIR=0
    NFPR=AP%NFPR
    IF(NFPRS/=NFPR)THEN
       NODIR=1
    ELSE
       DO I=1,NFPR
          IF(ICPRS(I)/=ICP(I)) THEN
             NODIR=1
             EXIT
          ENDIF
       ENDDO
    ENDIF
    DEALLOCATE(ICPRS)

  END SUBROUTINE STPNAE

!-----------------------------------------------------------------------
!-----------------------------------------------------------------------
!  Subroutines for the Continuation of Folds (Algebraic Problems)
!-----------------------------------------------------------------------
!-----------------------------------------------------------------------

! ---------- ----
  SUBROUTINE FNLP(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,DFDU,DFDP)

    ! Generates the equations for the 2-par continuation of folds.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM,IJAC
    DOUBLE PRECISION, INTENT(IN) :: UOLD(*)
    DOUBLE PRECISION, INTENT(INOUT) :: U(NDIM),PAR(*)
    DOUBLE PRECISION, INTENT(OUT) :: F(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: DFDU(NDIM,NDIM),DFDP(NDIM,*)

    CALL FNLPF(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,DFDU,DFDP,FUNI)

  END SUBROUTINE FNLP

! ---------- -----
  SUBROUTINE FNLPF(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,DFDU,DFDP,FUNI)

    ! Generates the equations for the 2-par continuation of folds.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM,IJAC
    DOUBLE PRECISION, INTENT(IN) :: UOLD(*)
    DOUBLE PRECISION, INTENT(INOUT) :: U(NDIM),PAR(*)
    DOUBLE PRECISION, INTENT(OUT) :: F(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: DFDU(NDIM,NDIM),DFDP(NDIM,*)
    include 'interfaces.h'
    ! Local
    DOUBLE PRECISION, ALLOCATABLE :: DFU(:,:),DFP(:,:),FF1(:),FF2(:)
    INTEGER NDM,NPAR,I,II,J,IJC
    DOUBLE PRECISION UMX,EP,P,UU

    NDM=AP%NDM
    NPAR=AP%NPAR

    IF(NDIM==NDM)THEN ! reduced function for Cusp detection
       CALL FUNI(AP,NDM,U,UOLD,ICP,PAR,0,F,DFDU,DFDP)
       RETURN
    ENDIF

    ! Generate the function.

    ALLOCATE(DFU(NDM,NDM),DFP(NDM,NPAR))
    IF(IJAC==0)THEN
       IJC=IJAC
    ELSE
       IJC=2
    ENDIF
    CALL FFLP(AP,NDIM,U,UOLD,ICP,PAR,IJC,F,NDM,DFU,DFP,FUNI)

    IF(IJAC.EQ.0)THEN
       DEALLOCATE(DFU,DFP)
       RETURN
    ENDIF
    ALLOCATE(FF1(NDIM),FF2(NDIM))

    ! Generate the Jacobian.

    UMX=0.d0
    DO I=1,NDM
       IF(DABS(U(I)).GT.UMX)UMX=DABS(U(I))
    ENDDO

    EP=HMACH*(1+UMX)

    DFDU(1:NDM,1:NDM)=DFU(:,:)
    DFDU(1:NDM,NDM+1:2*NDM)=0d0
    DFDU(1:NDM,NDIM)=DFP(:,ICP(2))

    DFDU(NDM+1:2*NDM,NDM+1:2*NDM)=DFU(:,:)
    IF(AP%ITPST==7)THEN ! PD bif for maps
       DO I=1,NDM
          DFDU(NDM+I,NDM+I)=DFDU(NDM+I,NDM+I)+2
       ENDDO
    ENDIF

    DFDU(NDIM,1:NDM)=0d0
    DFDU(NDIM,NDM+1:2*NDM)=2*U(NDM+1:NDM*2)
    DFDU(NDIM,NDIM)=0d0

    IF(IJAC/=1)THEN
       DFDP(1:NDM,ICP(1))=DFP(:,ICP(1))
    ENDIF

    DO II=1,NDM+1
       I=II
       IF(I>NDM)I=NDIM
       UU=U(I)
       U(I)=UU-EP
       CALL FFLP(AP,NDIM,U,UOLD,ICP,PAR,0,FF1,NDM,DFU,DFP,FUNI)
       U(I)=UU+EP
       CALL FFLP(AP,NDIM,U,UOLD,ICP,PAR,0,FF2,NDM,DFU,DFP,FUNI)
       U(I)=UU
       DO J=NDM+1,2*NDM
          DFDU(J,I)=(FF2(J)-FF1(J))/(2*EP)
       ENDDO
    ENDDO

    DEALLOCATE(FF2)
    IF(IJAC.EQ.1)THEN
       DEALLOCATE(FF1,DFU,DFP)
       RETURN
    ENDIF
    P=PAR(ICP(1))
    PAR(ICP(1))=P+EP

    CALL FFLP(AP,NDIM,U,UOLD,ICP,PAR,0,FF1,NDM,DFU,DFP,FUNI)

    DO J=NDM+1,2*NDM
       DFDP(J,ICP(1))=(FF1(J)-F(J))/EP
    ENDDO
    DFDP(NDIM,ICP(1))=0d0

    PAR(ICP(1))=P
    DEALLOCATE(FF1,DFU,DFP)

  END SUBROUTINE FNLPF

! ---------- ----
  SUBROUTINE FFLP(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,NDM,DFDU,DFDP,FUNI)

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM,NDM,IJAC
    DOUBLE PRECISION, INTENT(IN) :: UOLD(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: U(NDIM),PAR(*)
    DOUBLE PRECISION, INTENT(OUT) :: F(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: DFDU(NDM,NDM),DFDP(NDM,*)
    include 'interfaces.h'

    INTEGER IJC,I,J

    PAR(ICP(2))=U(NDIM)
    IJC=MAX(IJAC,1)
    CALL FUNI(AP,NDM,U,UOLD,ICP,PAR,IJC,F,DFDU,DFDP)

    DO I=1,NDM
       F(NDM+I)=0.d0
       DO J=1,NDM
          F(NDM+I)=F(NDM+I)+DFDU(I,J)*U(NDM+J)
       ENDDO
    ENDDO
    IF(AP%ITPST==7)THEN ! PD bif for maps
       DO I=1,NDM
          F(NDM+I)=F(NDM+I)+2*U(NDM+I)
       ENDDO
    ENDIF

    F(NDIM)=-1

    DO I=1,NDM
       F(NDIM)=F(NDIM)+U(NDM+I)*U(NDM+I)
    ENDDO

  END SUBROUTINE FFLP

! ---------- -------
  SUBROUTINE STPNLP(AP,PAR,ICP,U,UDOT,NODIR)

    ! Generates starting data for the continuation of folds.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*)
    INTEGER, INTENT(OUT) :: NODIR
    DOUBLE PRECISION, INTENT(OUT) :: PAR(*),U(*),UDOT(*)

    CALL STPNLPF(AP,PAR,ICP,U,UDOT,NODIR,FUNI)

  END SUBROUTINE STPNLP

! ---------- -------
  SUBROUTINE STPNLPF(AP,PAR,ICP,U,UDOT,NODIR,FUNI)

    USE IO
    USE SUPPORT

    ! Generates starting data for the continuation of folds.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*)
    INTEGER, INTENT(OUT) :: NODIR
    DOUBLE PRECISION, INTENT(OUT) :: PAR(*),U(*),UDOT(*)
    include 'interfaces.h'
    ! Local
    DOUBLE PRECISION, ALLOCATABLE :: DFU(:,:),V(:),F(:)
    DOUBLE PRECISION DUMDFP(1)
    INTEGER ICPRS(2),NDIM,NDM,I

    NDIM=AP%NDIM
    NDM=AP%NDM

    IF(ABS(AP%ITP)/10>0)THEN
       ! restart
       CALL STPNAE(AP,PAR,ICP,U,UDOT,NODIR)
       U(NDIM)=PAR(ICP(2))
       RETURN
    ENDIF

    CALL READLB(AP,ICPRS,U,UDOT,PAR)

    ALLOCATE(DFU(NDM,NDM),V(NDM),F(NDM))
    CALL FUNI(AP,NDM,U,U,ICP,PAR,1,F,DFU,DUMDFP)
    IF(AP%ITPST==7)THEN ! PD bif for maps
       DO I=1,NDM
          DFU(I,I)=DFU(I,I)+2
       ENDDO
    ENDIF
    CALL NLVC(NDM,NDM,1,DFU,V)
    CALL NRMLZ(NDM,V)
    DO I=1,NDM
       U(NDM+I)=V(I)
    ENDDO
    DEALLOCATE(DFU,V,F)
    U(NDIM)=PAR(ICP(2))
    NODIR=1

  END SUBROUTINE STPNLPF

!-----------------------------------------------------------------------
!-----------------------------------------------------------------------
!   Subroutines for BP cont (Algebraic Problems) (by F. Dercole)
!-----------------------------------------------------------------------
!-----------------------------------------------------------------------

! ---------- ----
  SUBROUTINE FNBP(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,DFDU,DFDP)

    ! Generates the equations for the 2-par continuation of BP.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM,IJAC
    DOUBLE PRECISION, INTENT(IN) :: UOLD(*)
    DOUBLE PRECISION, INTENT(INOUT) :: U(NDIM),PAR(*)
    DOUBLE PRECISION, INTENT(OUT) :: F(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: DFDU(NDIM,NDIM),DFDP(NDIM,*)

    CALL FNBPF(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,DFDU,DFDP,FUNI)

  END SUBROUTINE FNBP

! ---------- -----
  SUBROUTINE FNBPF(AP,NDIM,U,UOLD,ICP,PAR,IJAC,F,DFDU,DFDP,FUNI)

    ! Generates the equations for the 2-par continuation of BP.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM,IJAC
    DOUBLE PRECISION, INTENT(IN) :: UOLD(*)
    DOUBLE PRECISION, INTENT(INOUT) :: U(NDIM),PAR(*)
    DOUBLE PRECISION, INTENT(OUT) :: F(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: DFDU(NDIM,NDIM),DFDP(NDIM,*)
    include 'interfaces.h'
    ! Local
    DOUBLE PRECISION, ALLOCATABLE :: DFU(:),DFP(:),FF1(:),FF2(:)
    INTEGER NDM,NPAR,I,J
    DOUBLE PRECISION UMX,EP,P,UU

    NDM=AP%NDM
    NPAR=AP%NPAR

    ! Generate the function.

    ALLOCATE(DFU(NDM*NDM),DFP(NDM*NPAR))
    CALL FFBP(AP,NDIM,U,UOLD,ICP,PAR,F,NDM,DFU,DFP,FUNI)

    IF(IJAC.EQ.0)THEN
       DEALLOCATE(DFU,DFP)
       RETURN
    ENDIF
    ALLOCATE(FF1(NDIM),FF2(NDIM))

    ! Generate the Jacobian.

    UMX=0.d0
    DO I=1,NDIM
       IF(DABS(U(I)).GT.UMX)UMX=DABS(U(I))
    ENDDO

    EP=HMACH*(1+UMX)

    DO I=1,NDIM
       UU=U(I)
       U(I)=UU-EP
       CALL FFBP(AP,NDIM,U,UOLD,ICP,PAR,FF1,NDM,DFU,DFP,FUNI)
       U(I)=UU+EP
       CALL FFBP(AP,NDIM,U,UOLD,ICP,PAR,FF2,NDM,DFU,DFP,FUNI)
       U(I)=UU
       DO J=1,NDIM
          DFDU(J,I)=(FF2(J)-FF1(J))/(2*EP)
       ENDDO
    ENDDO

    DEALLOCATE(FF2)
    IF(IJAC.EQ.1)THEN
       DEALLOCATE(FF1,DFU,DFP)
       RETURN
    ENDIF
    P=PAR(ICP(1))
    PAR(ICP(1))=P+EP

    CALL FFBP(AP,NDIM,U,UOLD,ICP,PAR,FF1,NDM,DFU,DFP,FUNI)

    DO J=1,NDIM
       DFDP(J,ICP(1))=(FF1(J)-F(J))/EP
    ENDDO

    PAR(ICP(1))=P
    DEALLOCATE(FF1,DFU,DFP)

  END SUBROUTINE FNBPF

! ---------- ----
  SUBROUTINE FFBP(AP,NDIM,U,UOLD,ICP,PAR,F,NDM,DFDU,DFDP,FUNI)

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM,NDM
    DOUBLE PRECISION, INTENT(IN) :: UOLD(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: U(NDIM),PAR(*)
    DOUBLE PRECISION, INTENT(OUT) :: F(NDIM)
    DOUBLE PRECISION, INTENT(INOUT) :: DFDU(NDM,NDM),DFDP(NDM,*)
    include 'interfaces.h'

    INTEGER ISW,I,J

    ISW=AP%ISW

    IF(ISW.EQ.3) THEN
       !        ** Generic case
       PAR(ICP(3))=U(NDIM)
    ENDIF
    PAR(ICP(2))=U(NDIM-1)

    CALL FUNI(AP,NDM,U,UOLD,ICP,PAR,2,F,DFDU,DFDP)

    IF(ISW.EQ.2) THEN
       !        ** Non-generic case
       DO I=1,NDM
          F(I)=F(I)+U(NDIM)*U(NDM+I)
       ENDDO
    ENDIF

    DO I=1,NDM
       F(NDM+I)=0.d0
       DO J=1,NDM
          F(NDM+I)=F(NDM+I)+DFDU(J,I)*U(NDM+J)
       ENDDO
    ENDDO

    F(NDIM-1)=0.d0
    DO I=1,NDM
       F(NDIM-1)=F(NDIM-1)+DFDP(I,ICP(1))*U(NDM+I)
    ENDDO

    F(NDIM)=-1
    DO I=1,NDM
       F(NDIM)=F(NDIM)+U(NDM+I)*U(NDM+I)
    ENDDO

  END SUBROUTINE FFBP

! ---------- ------
  SUBROUTINE STPNBP(AP,PAR,ICP,U,UDOT,NODIR)

    ! Generates starting data for the continuation of BP.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*)
    INTEGER, INTENT(OUT) :: NODIR
    DOUBLE PRECISION, INTENT(OUT) :: PAR(*),U(*),UDOT(*)

    CALL STPNBPF(AP,PAR,ICP,U,UDOT,NODIR,FUNI)

  END SUBROUTINE STPNBP

! ---------- -------
  SUBROUTINE STPNBPF(AP,PAR,ICP,U,UDOT,NODIR,FUNI)

    USE IO
    USE SUPPORT

    ! Generates starting data for the continuation of BP.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(IN) :: ICP(*)
    INTEGER, INTENT(OUT) :: NODIR
    DOUBLE PRECISION, INTENT(OUT) :: PAR(*),U(*),UDOT(*)
    include 'interfaces.h'

    ! Local
    DOUBLE PRECISION, ALLOCATABLE ::DFU(:,:),DFP(:,:),A(:,:),V(:),F(:)
    INTEGER :: ICPRS(3),NDIM,ISW,NDM,NPAR,I,J

    NDIM=AP%NDIM
    ISW=AP%ISW
    NDM=AP%NDM
    NPAR=AP%NPAR

    IF(ABS(AP%ITP)/10>0)THEN
       ! restart
       CALL STPNAE(AP,PAR,ICP,U,UDOT,NODIR)
       U(NDIM-1)=PAR(ICP(2))
       IF(ISW==3) THEN 
          U(NDIM)=PAR(ICP(3)) ! Generic case
       ELSE
          U(NDIM)=0.d0        ! Non-generic case
       ENDIF
       RETURN
    ENDIF

    CALL READLB(AP,ICPRS,U,UDOT,PAR)

    ALLOCATE(DFU(NDM,NDM),DFP(NDM,NPAR),A(NDM,NDM+1))
    ALLOCATE(V(NDM+1),F(NDM))
    CALL FUNI(AP,NDM,U,U,ICP,PAR,2,F,DFU,DFP)
    A(:,1:NDM)=DFU(:,:)
    A(:,NDM+1)=DFP(:,ICP(1))
    CALL NLVC(NDM,NDM+1,2,A,V)
    DEALLOCATE(A)
    ALLOCATE(A(NDM+1,NDM+1))
    DO I=1,NDM
       DO J=1,NDM
          A(I,J)=DFU(J,I)
       ENDDO
       A(NDM+1,I)=DFP(I,ICP(1))
    ENDDO
    DO I=1,NDM+1
       A(I,NDM+1)=V(I)
    ENDDO
    CALL NLVC(NDM+1,NDM+1,1,A,V)
    CALL NRMLZ(NDM,V)
    DO I=1,NDM
       U(NDM+I)=V(I)
    ENDDO
    DEALLOCATE(DFU,DFP,A,V,F)
    U(NDIM-1)=PAR(ICP(2))
    IF(ISW.EQ.3) THEN
       !        ** Generic case
       U(NDIM)=PAR(ICP(3))
    ELSE
       !        ** Non-generic case
       U(NDIM)=0.d0
    ENDIF

    NODIR=1
  END SUBROUTINE STPNBPF

! ------ --------- -------- ------
  DOUBLE PRECISION FUNCTION FNCSAE(AP,ICP,U,NDIM,PAR,ITEST,ITP) RESULT(Q)

    USE AUTO_CONSTANTS, ONLY: AUTOPARAMETERS
    TYPE(AUTOPARAMETERS), INTENT(INOUT) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM
    DOUBLE PRECISION, INTENT(IN) :: U(*)
    DOUBLE PRECISION, INTENT(INOUT) :: PAR(*)
    INTEGER, INTENT(IN) :: ITEST
    INTEGER, INTENT(OUT) :: ITP

    Q=FNCSAEF(AP,ICP,U,NDIM,PAR,ITEST,ITP,FUNI)

  END FUNCTION FNCSAE

! ------ --------- -------- -------
  DOUBLE PRECISION FUNCTION FNCSAEF(AP,ICP,U,NDIM,PAR,ITEST,ITP,FUNI) RESULT(Q)

    USE SUPPORT, ONLY: AA=>P0V, PI
    USE AUTO_CONSTANTS, ONLY: AUTOPARAMETERS

    include 'interfaces.h'

    TYPE(AUTOPARAMETERS), INTENT(INOUT) :: AP
    INTEGER, INTENT(IN) :: ICP(*),NDIM
    DOUBLE PRECISION, INTENT(IN) :: U(*)
    DOUBLE PRECISION, INTENT(INOUT) :: PAR(*)
    INTEGER, INTENT(IN) :: ITEST
    INTEGER, INTENT(OUT) :: ITP

    Q=0.d0
    ITP=0
    SELECT CASE(ITEST)
    CASE(0)
       CALL PVLSI(AP,U,NDIM,PAR)
    CASE(1) ! Check for fold
       Q=FNLPAE(AP,ITP,AA)
    CASE(2) ! Check for branch point
       Q=FNBPAE(AP,ITP)
    CASE(3) ! Check for cusp on fold
       Q=FNCPAE(AP,PAR,ICP,ITP,FUNI,U,AA)
    END SELECT

  END FUNCTION FNCSAEF

! ------ --------- -------- ------
  DOUBLE PRECISION FUNCTION FNBPAE(AP,ITP)

    USE SUPPORT, ONLY: CHECKSP

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(OUT) :: ITP

    INTEGER IID,IBR,NTOT,NTOP
    DOUBLE PRECISION DET

    ITP=0
    FNBPAE=0d0
    IF(.NOT.CHECKSP('BP',AP%IPS,AP%ILP,AP%ISP))RETURN

    IID=AP%IID
    IBR=AP%IBR
    NTOT=AP%NTOT
    NTOP=MOD(NTOT-1,9999)+1

    DET=AP%DET
    FNBPAE=DET
    ITP=1+10*AP%ITPST

! If requested write additional output on unit 9 :

    IF(IID.GE.2)WRITE(9,101)IBR,NTOP+1,FNBPAE
101 FORMAT(I4,I6,9X,'BP   Function:',ES14.5)

  END FUNCTION FNBPAE

! ------ --------- -------- ------
  DOUBLE PRECISION FUNCTION FNLPAE(AP,ITP,AA)

    USE SUPPORT

    TYPE(AUTOPARAMETERS), INTENT(INOUT) :: AP
    INTEGER, INTENT(OUT) :: ITP
    DOUBLE PRECISION, INTENT(IN) :: AA(AP%NDIM+1,AP%NDIM+1)
! Local
    DOUBLE PRECISION, ALLOCATABLE :: UD(:),AAA(:,:),RHS(:)

    INTEGER NDIM,IID,IBR,NTOT,NTOP
    DOUBLE PRECISION DET

    ITP=0
    FNLPAE=0d0
    IF(.NOT.CHECKSP('LP',AP%IPS,AP%ILP,AP%ISP))RETURN

    NDIM=AP%NDIM
    IID=AP%IID
    IBR=AP%IBR
    NTOT=AP%NTOT
    NTOP=MOD(NTOT-1,9999)+1

    ALLOCATE(AAA(NDIM+1,NDIM+1),RHS(NDIM+1))
    AAA(:,:)=AA(:,:)
    RHS(1:NDIM)=0.d0
    RHS(NDIM+1)=1.d0

    ALLOCATE(UD(NDIM+1))
    CALL GEL(NDIM+1,AAA,1,UD,RHS,DET)
!   don't store DET here: it is for a different matrix than
!   used with pseudo arclength continuation and sometimes has
!   a  different sign
    CALL NRMLZ(NDIM+1,UD)
    FNLPAE=UD(NDIM+1)
    DEALLOCATE(UD,AAA,RHS)
    AP%FLDF=FNLPAE
    ITP=2+10*AP%ITPST

! If requested write additional output on unit 9 :

    IF(IID.GE.2)WRITE(9,101)ABS(IBR),NTOP+1,FNLPAE
101 FORMAT(I4,I6,9X,'Fold Function:',ES14.5)

  END FUNCTION FNLPAE

! ---------- -------
  SUBROUTINE RNULLVC(AP,AA,V)

    ! get null vector for the transposed Jacobian for BT/CP detection

    USE SUPPORT, ONLY: NLVC, NRMLZ

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    DOUBLE PRECISION, INTENT(IN) :: AA(AP%NDIM+1,AP%NDIM+1)
    DOUBLE PRECISION, INTENT(INOUT) :: V(AP%NDM)

    DOUBLE PRECISION, ALLOCATABLE :: DFU(:,:)
    DOUBLE PRECISION, ALLOCATABLE, SAVE :: VOLD(:)
    INTEGER NDM,I

    NDM=AP%NDM
    IF(.NOT.ALLOCATED(VOLD))THEN
       ALLOCATE(VOLD(NDM))
       VOLD(:)=0
    ENDIF
    ALLOCATE(DFU(NDM,NDM))
    DO I=1,NDM
       DFU(1:NDM,I)=AA(NDM+I,NDM+1:2*NDM)
    ENDDO
    CALL NLVC(NDM,NDM,1,DFU,V)
    CALL NRMLZ(NDM,V)
    IF(DOT_PRODUCT(V,VOLD)<0)THEN
       V(:)=-V(:)
    ENDIF
    VOLD(:)=V(:)
    DEALLOCATE(DFU)
  END SUBROUTINE RNULLVC

! ------ --------- -------- ------
  DOUBLE PRECISION FUNCTION FNBTAE(AP,U,AA)

    ! evaluate Bogdanov-Takens/1:1/1:2-resonance test function
    ! this function is used by equilibrium.f90 and maps.f90.

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    DOUBLE PRECISION, INTENT(IN) :: U(AP%NDIM), AA(AP%NDIM+1,AP%NDIM+1)
! Local
    INTEGER NDM
    DOUBLE PRECISION, ALLOCATABLE :: V(:)

    FNBTAE = 0

    NDM=AP%NDM

    ! take the inner product with the null vector for the Jacobian
    ALLOCATE(V(NDM))
    CALL RNULLVC(AP,AA,V)
    FNBTAE = DOT_PRODUCT(U(NDM+1:2*NDM),V(1:NDM))
    DEALLOCATE(V)

  END FUNCTION FNBTAE

! ------ --------- -------- ------
  DOUBLE PRECISION FUNCTION FNCPAE(AP,PAR,ICP,ITP,FUNI,U,AA)

    USE SUPPORT, ONLY: CHECKSP

    include 'interfaces.h'

    TYPE(AUTOPARAMETERS), INTENT(IN) :: AP
    INTEGER, INTENT(OUT) :: ITP
    DOUBLE PRECISION, INTENT(IN) :: U(AP%NDIM),AA(AP%NDM)
    INTEGER, INTENT(IN) :: ICP(*)
    DOUBLE PRECISION, INTENT(INOUT) :: PAR(*)
! Local
    DOUBLE PRECISION, ALLOCATABLE :: F(:),UU(:),V(:)
    DOUBLE PRECISION DUM(1),H
    INTEGER NDM,NTOP,I

    FNCPAE = 0
    ITP=0
    IF(AP%ISW/=2.OR.AP%ITPST/=2.OR..NOT.CHECKSP('CP',AP%IPS,AP%ILP,AP%ISP))THEN
       RETURN
    ENDIF

    NDM=AP%NDM
    ALLOCATE(UU(NDM),F(NDM),V(NDM))

    CALL RNULLVC(AP,AA,V)

    ! Evaluate cusp function:
    H=0.d0
    DO I=1,NDM
       IF(ABS(U(I))>H)H=ABS(U(I))
    ENDDO
    H=(EPSILON(H)**(1d0/3))*(1+H)

    UU(:)=U(:NDM)+U(NDM+1:2*NDM)*H
    CALL FUNI(AP,NDM,UU,UU,ICP,PAR,0,F,DUM,DUM)
    FNCPAE=DOT_PRODUCT(V(:),F(:))
    UU(:)=U(:NDM)-U(NDM+1:2*NDM)*H
    CALL FUNI(AP,NDM,UU,UU,ICP,PAR,0,F,DUM,DUM)
    FNCPAE=(FNCPAE+DOT_PRODUCT(V(:),F(:)))/H**2

    DEALLOCATE(UU,F,V)
    ITP=-22

    NTOP=MOD(AP%NTOT-1,9999)+1
    IF(AP%IID.GE.2)WRITE(9,101)ABS(AP%IBR),NTOP+1,FNCPAE
101 FORMAT(I4,I6,9X,'Cusp Function:',ES14.5)

  END FUNCTION FNCPAE

END MODULE TOOLBOXAE