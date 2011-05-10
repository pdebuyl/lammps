// **************************************************************************
//                               re_squared_lj.cu
//                             -------------------
//                               W. Michael Brown
//
//  Device code for RE-Squared - Lennard-Jones potential acceleration
//
// __________________________________________________________________________
//    This file is part of the LAMMPS Accelerator Library (LAMMPS_AL)
// __________________________________________________________________________
//
//    begin                : Fri May 06 2011
//    email                : brownw@ornl.gov
// ***************************************************************************/

#ifndef RE_SQUARED_LJ_CU
#define RE_SQUARED_LJ_CU

#ifdef NV_KERNEL
#include "ellipsoid_extra.h"
#endif

#define SBBITS 30
#define NEIGHMASK 0x3FFFFFFF
__inline int sbmask(int j) { return j >> SBBITS & 3; }

__kernel void kernel_sphere_ellipsoid(__global numtyp4 *x_,__global numtyp4 *q,
                               __global numtyp4* shape,__global numtyp4* well, 
                               __global numtyp *gum, __global numtyp2* sig_eps, 
                               const int ntypes, __global numtyp *lshape, 
                               __global int *dev_nbor, const int stride, 
                               __global acctyp4 *ans, __global acctyp *engv, 
                               __global int *err_flag, const int eflag, 
                               const int vflag,const int start, const int inum, 
                               const int nall, const int t_per_atom) {
  int tid=THREAD_ID_X;
  int ii=mul24((int)BLOCK_ID_X,(int)(BLOCK_SIZE_X)/t_per_atom);
  ii+=tid/t_per_atom+start;
  int offset=tid%t_per_atom;

  __local numtyp sp_lj[4];
  sp_lj[0]=gum[3];    
  sp_lj[1]=gum[4];    
  sp_lj[2]=gum[5];    
  sp_lj[3]=gum[6];    

  acctyp energy=(acctyp)0;
  acctyp4 f;
  f.x=(acctyp)0;
  f.y=(acctyp)0;
  f.z=(acctyp)0;
  acctyp virial[6];
  for (int i=0; i<6; i++)
    virial[i]=(acctyp)0;

  if (ii<inum) {
    __global int *nbor=dev_nbor+ii;
    int i=*nbor;
    nbor+=stride;
    int numj=*nbor;
    nbor+=stride;
    __global int *nbor_end=nbor+stride*numj;
    nbor+=mul24(offset,stride);
    int n_stride=mul24(t_per_atom,stride);
  
    numtyp4 ix=x_[i];
    int itype=ix.w;
      
    numtyp oner=shape[itype].x;
    numtyp one_well=well[itype].x;
  
    numtyp factor_lj;
    for ( ; nbor<nbor_end; nbor+=n_stride) {
  
      int j=*nbor;
      factor_lj = sp_lj[sbmask(j)];
      j &= NEIGHMASK;

      numtyp4 jx=x_[j];
      int jtype=jx.w;

      // Compute r12
      numtyp r12[3];
      r12[0] = jx.x-ix.x;
      r12[1] = jx.y-ix.y;
      r12[2] = jx.z-ix.z;
      numtyp ir = gpu_dot3(r12,r12);

      ir = rsqrt(ir);
      numtyp r = (numtyp)1.0/ir;
      
      numtyp r12hat[3];
      r12hat[0]=r12[0]*ir;
      r12hat[1]=r12[1]*ir;
      r12hat[2]=r12[2]*ir;

      numtyp a2[9];
      gpu_quat_to_mat_trans(q,j,a2);
  
      numtyp u_r, dUr[3], eta;
      { // Compute U_r, dUr, eta, and teta
        // Compute g12
        numtyp g12[9];
        {
          {
            numtyp g2[9];
            gpu_diag_times3(shape[jtype],a2,g12);
            gpu_transpose_times3(a2,g12,g2);
            g12[0]=g2[0]+oner;
            g12[4]=g2[4]+oner;
            g12[8]=g2[8]+oner;
            g12[1]=g2[1];
            g12[2]=g2[2];
            g12[3]=g2[3];
            g12[5]=g2[5];
            g12[6]=g2[6];
            g12[7]=g2[7];    
          }
  
          { // Compute U_r and dUr
    
            // Compute kappa
            numtyp kappa[3];
            gpu_mldivide3(g12,r12,kappa,err_flag);

            // -- kappa is now / r
            kappa[0]*=ir;
            kappa[1]*=ir;
            kappa[2]*=ir;
  
            // energy
  
            // compute u_r and dUr
            numtyp uslj_rsq;
            {
              // Compute distance of closest approach
              numtyp h12, sigma12;
              sigma12 = gpu_dot3(r12hat,kappa);
              sigma12 = rsqrt((numtyp)0.5*sigma12);
              h12 = r-sigma12;

              // -- kappa is now ok
              kappa[0]*=r;
              kappa[1]*=r;
              kappa[2]*=r;
          
              int mtype=mul24(ntypes,itype)+jtype;
              numtyp sigma = sig_eps[mtype].x;
              numtyp epsilon = sig_eps[mtype].y;
              numtyp varrho = sigma/(h12+gum[0]*sigma);
              numtyp varrho6 = varrho*varrho*varrho;
              varrho6*=varrho6;
              numtyp varrho12 = varrho6*varrho6;
              u_r = (numtyp)4.0*epsilon*(varrho12-varrho6);

              numtyp temp1 = ((numtyp)2.0*varrho12*varrho-varrho6*varrho)/sigma;
              temp1 = temp1*(numtyp)24.0*epsilon;
              uslj_rsq = temp1*sigma12*sigma12*sigma12*(numtyp)0.5;
              numtyp temp2 = gpu_dot3(kappa,r12hat);
              uslj_rsq = uslj_rsq*ir*ir;

              dUr[0] = temp1*r12hat[0]+uslj_rsq*(kappa[0]-temp2*r12hat[0]);
              dUr[1] = temp1*r12hat[1]+uslj_rsq*(kappa[1]-temp2*r12hat[1]);
              dUr[2] = temp1*r12hat[2]+uslj_rsq*(kappa[2]-temp2*r12hat[2]);
            }
          }
        }
     
        // Compute eta
        {
          eta = (numtyp)2.0*lshape[itype]*lshape[jtype];
          numtyp det_g12 = gpu_det3(g12);
          eta = pow(eta/det_g12,gum[1]);
        }
      }
  
      numtyp chi, dchi[3];
      { // Compute chi and dchi

        // Compute b12
        numtyp b12[9];
        {
          numtyp b2[9];
          gpu_diag_times3(well[jtype],a2,b12);
          gpu_transpose_times3(a2,b12,b2);
          b12[0]=b2[0]+one_well;
          b12[4]=b2[4]+one_well;
          b12[8]=b2[8]+one_well;
          b12[1]=b2[1];
          b12[2]=b2[2];
          b12[3]=b2[3];
          b12[5]=b2[5];
          b12[6]=b2[6];
          b12[7]=b2[7];    
        }

        // compute chi_12
        numtyp iota[3];
        gpu_mldivide3(b12,r12,iota,err_flag);
        // -- iota is now iota/r
        iota[0]*=ir;
        iota[1]*=ir;
        iota[2]*=ir;
        chi = gpu_dot3(r12hat,iota);
        chi = pow(chi*(numtyp)2.0,gum[2]);

        // -- iota is now ok
        iota[0]*=r;
        iota[1]*=r;
        iota[2]*=r;

        numtyp temp1 = gpu_dot3(iota,r12hat);
        numtyp temp2 = (numtyp)-4.0*ir*ir*gum[2]*pow(chi,(gum[2]-(numtyp)1.0)/
                                                     gum[2]);
        dchi[0] = temp2*(iota[0]-temp1*r12hat[0]);
        dchi[1] = temp2*(iota[1]-temp1*r12hat[1]);
        dchi[2] = temp2*(iota[2]-temp1*r12hat[2]);
      }

      numtyp temp2 = factor_lj*eta*chi;
      if (eflag>0)
        energy+=u_r*temp2;
      numtyp temp1 = -eta*u_r*factor_lj;
      if (vflag>0) {
        r12[0]*=-1;
        r12[1]*=-1;
        r12[2]*=-1;
        numtyp ft=temp1*dchi[0]-temp2*dUr[0];
        f.x+=ft;
        virial[0]+=r12[0]*ft;
        ft=temp1*dchi[1]-temp2*dUr[1];
        f.y+=ft;
        virial[1]+=r12[1]*ft;
        virial[3]+=r12[0]*ft;
        ft=temp1*dchi[2]-temp2*dUr[2];
        f.z+=ft;
        virial[2]+=r12[2]*ft;
        virial[4]+=r12[0]*ft;
        virial[5]+=r12[1]*ft;
      } else {
        f.x+=temp1*dchi[0]-temp2*dUr[0];
        f.y+=temp1*dchi[1]-temp2*dUr[1];
        f.z+=temp1*dchi[2]-temp2*dUr[2];
      }
    } // for nbor
  } // if ii
  
  // Reduce answers
  if (t_per_atom>1) {
    __local acctyp red_acc[6][BLOCK_PAIR];
    
    red_acc[0][tid]=f.x;
    red_acc[1][tid]=f.y;
    red_acc[2][tid]=f.z;
    red_acc[3][tid]=energy;

    for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
      if (offset < s) {
        for (int r=0; r<4; r++)
          red_acc[r][tid] += red_acc[r][tid+s];
      }
    }
    
    f.x=red_acc[0][tid];
    f.y=red_acc[1][tid];
    f.z=red_acc[2][tid];
    energy=red_acc[3][tid];

    if (vflag>0) {
      for (int r=0; r<6; r++)
        red_acc[r][tid]=virial[r];

      for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
        if (offset < s) {
          for (int r=0; r<6; r++)
            red_acc[r][tid] += red_acc[r][tid+s];
        }
      }
    
      for (int r=0; r<6; r++)
        virial[r]=red_acc[r][tid];
    }
  }

  // Store answers
  if (ii<inum && offset==0) {
    __global acctyp *ap1=engv+ii;
    if (eflag>0) {
      *ap1=energy;
      ap1+=inum;
    }
    if (vflag>0) {
      for (int i=0; i<6; i++) {
        *ap1=virial[i];
        ap1+=inum;
      }
    }
    ans[ii]=f;
  } // if ii
}

__kernel void kernel_lj(__global numtyp4 *x_, __global numtyp4 *lj1, 
                        __global numtyp4* lj3, const int lj_types, 
                        __global numtyp *gum, 
                        const int stride, __global int *dev_ij, 
                        __global acctyp4 *ans, __global acctyp *engv, 
                        __global int *err_flag, const int eflag, 
                        const int vflag, const int start, const int inum, 
                        const int nall, const int t_per_atom) {
  int tid=THREAD_ID_X;
  int ii=mul24((int)BLOCK_ID_X,(int)(BLOCK_SIZE_X)/t_per_atom);
  ii+=tid/t_per_atom+start;
  int offset=tid%t_per_atom;

  __local numtyp sp_lj[4];
  sp_lj[0]=gum[3];    
  sp_lj[1]=gum[4];    
  sp_lj[2]=gum[5];    
  sp_lj[3]=gum[6];    

  acctyp energy=(acctyp)0;
  acctyp4 f;
  f.x=(acctyp)0;
  f.y=(acctyp)0;
  f.z=(acctyp)0;
  acctyp virial[6];
  for (int i=0; i<6; i++)
    virial[i]=(acctyp)0;
  
  if (ii<inum) {
    __global int *nbor=dev_ij+ii;
    int i=*nbor;
    nbor+=stride;
    int numj=*nbor;
    nbor+=stride;
    __global int *list_end=nbor+mul24(stride,numj);
    nbor+=mul24(offset,stride);
    int n_stride=mul24(t_per_atom,stride);
  
    numtyp4 ix=x_[i];
    int itype=ix.w;

    numtyp factor_lj;
    for ( ; nbor<list_end; nbor+=n_stride) {
  
      int j=*nbor;
      factor_lj = sp_lj[sbmask(j)];
      j &= NEIGHMASK;

      numtyp4 jx=x_[j];
      int jtype=jx.w;

      // Compute r12
      numtyp delx = ix.x-jx.x;
      numtyp dely = ix.y-jx.y;
      numtyp delz = ix.z-jx.z;
      numtyp r2inv = delx*delx+dely*dely+delz*delz;
        
      int ii=itype*lj_types+jtype;
      if (r2inv<lj1[ii].z && lj1[ii].w==SPHERE_SPHERE) {
        r2inv=(numtyp)1.0/r2inv;
        numtyp r6inv = r2inv*r2inv*r2inv;
        numtyp force = r2inv*r6inv*(lj1[ii].x*r6inv-lj1[ii].y);
        force*=factor_lj;
      
        f.x+=delx*force;
        f.y+=dely*force;
        f.z+=delz*force;

        if (eflag>0) {
          numtyp e=r6inv*(lj3[ii].x*r6inv-lj3[ii].y);
          energy+=factor_lj*(e-lj3[ii].z); 
        }
        if (vflag>0) {
          virial[0] += delx*delx*force;
          virial[1] += dely*dely*force;
          virial[2] += delz*delz*force;
          virial[3] += delx*dely*force;
          virial[4] += delx*delz*force;
          virial[5] += dely*delz*force;
        }
      }

    } // for nbor
  } // if ii
  
  // Reduce answers
  if (t_per_atom>1) {
    __local acctyp red_acc[6][BLOCK_PAIR];
    
    red_acc[0][tid]=f.x;
    red_acc[1][tid]=f.y;
    red_acc[2][tid]=f.z;
    red_acc[3][tid]=energy;

    for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
      if (offset < s) {
        for (int r=0; r<4; r++)
          red_acc[r][tid] += red_acc[r][tid+s];
      }
    }
    
    f.x=red_acc[0][tid];
    f.y=red_acc[1][tid];
    f.z=red_acc[2][tid];
    energy=red_acc[3][tid];

    if (vflag>0) {
      for (int r=0; r<6; r++)
        red_acc[r][tid]=virial[r];

      for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
        if (offset < s) {
          for (int r=0; r<6; r++)
            red_acc[r][tid] += red_acc[r][tid+s];
        }
      }
    
      for (int r=0; r<6; r++)
        virial[r]=red_acc[r][tid];
    }
  }

  // Store answers
  if (ii<inum && offset==0) {
    __global acctyp *ap1=engv+ii;
    if (eflag>0) {
      *ap1+=energy;
      ap1+=inum;
    }
    if (vflag>0) {
      for (int i=0; i<6; i++) {
        *ap1+=virial[i];
        ap1+=inum;
      }
    }
    acctyp4 old=ans[ii];
    old.x+=f.x;
    old.y+=f.y;
    old.z+=f.z;
    ans[ii]=old;
  } // if ii
}

__kernel void kernel_lj_fast(__global numtyp4 *x_, __global numtyp4 *lj1_in, 
                             __global numtyp4* lj3_in, __global numtyp *gum, 
                             const int stride, __global int *dev_ij,
                             __global acctyp4 *ans, __global acctyp *engv,
                             __global int *err_flag, const int eflag,
                             const int vflag, const int start, const int inum,
                             const int nall, const int t_per_atom) {
  int tid=THREAD_ID_X;
  int ii=mul24((int)BLOCK_ID_X,(int)(BLOCK_SIZE_X)/t_per_atom);
  ii+=tid/t_per_atom+start;
  int offset=tid%t_per_atom;

  __local numtyp sp_lj[4];                              
  __local numtyp4 lj1[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp4 lj3[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  if (tid<4)
    sp_lj[tid]=gum[tid+3];    
  if (tid<MAX_SHARED_TYPES*MAX_SHARED_TYPES) {
    lj1[tid]=lj1_in[tid];
    if (eflag>0)
      lj3[tid]=lj3_in[tid];
  }
  
  acctyp energy=(acctyp)0;
  acctyp4 f;
  f.x=(acctyp)0;
  f.y=(acctyp)0;
  f.z=(acctyp)0;
  acctyp virial[6];
  for (int i=0; i<6; i++)
    virial[i]=(acctyp)0;
  
  __syncthreads();
  
  if (ii<inum) {
    __global int *nbor=dev_ij+ii;
    int i=*nbor;
    nbor+=stride;
    int numj=*nbor;
    nbor+=stride;
    __global int *list_end=nbor+mul24(stride,numj);
    nbor+=mul24(offset,stride);
    int n_stride=mul24(t_per_atom,stride);

    numtyp4 ix=x_[i];
    int iw=ix.w;
    int itype=mul24((int)MAX_SHARED_TYPES,iw);

    numtyp factor_lj;
    for ( ; nbor<list_end; nbor+=n_stride) {
  
      int j=*nbor;
      factor_lj = sp_lj[sbmask(j)];
      j &= NEIGHMASK;

      numtyp4 jx=x_[j];
      int mtype=itype+jx.w;

      // Compute r12
      numtyp delx = ix.x-jx.x;
      numtyp dely = ix.y-jx.y;
      numtyp delz = ix.z-jx.z;
      numtyp r2inv = delx*delx+dely*dely+delz*delz;
        
      if (r2inv<lj1[mtype].z && lj1[mtype].w==SPHERE_SPHERE) {
        r2inv=(numtyp)1.0/r2inv;
        numtyp r6inv = r2inv*r2inv*r2inv;
        numtyp force = factor_lj*r2inv*r6inv*(lj1[mtype].x*r6inv-lj1[mtype].y);
      
        f.x+=delx*force;
        f.y+=dely*force;
        f.z+=delz*force;

        if (eflag>0) {
          numtyp e=r6inv*(lj3[mtype].x*r6inv-lj3[mtype].y);
          energy+=factor_lj*(e-lj3[mtype].z); 
        }
        if (vflag>0) {
          virial[0] += delx*delx*force;
          virial[1] += dely*dely*force;
          virial[2] += delz*delz*force;
          virial[3] += delx*dely*force;
          virial[4] += delx*delz*force;
          virial[5] += dely*delz*force;
        }
      }

    } // for nbor
  } // if ii
  
  // Reduce answers
  if (t_per_atom>1) {
    __local acctyp red_acc[6][BLOCK_PAIR];
    
    red_acc[0][tid]=f.x;
    red_acc[1][tid]=f.y;
    red_acc[2][tid]=f.z;
    red_acc[3][tid]=energy;

    for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
      if (offset < s) {
        for (int r=0; r<4; r++)
          red_acc[r][tid] += red_acc[r][tid+s];
      }
    }
    
    f.x=red_acc[0][tid];
    f.y=red_acc[1][tid];
    f.z=red_acc[2][tid];
    energy=red_acc[3][tid];

    if (vflag>0) {
      for (int r=0; r<6; r++)
        red_acc[r][tid]=virial[r];

      for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
        if (offset < s) {
          for (int r=0; r<6; r++)
            red_acc[r][tid] += red_acc[r][tid+s];
        }
      }
    
      for (int r=0; r<6; r++)
        virial[r]=red_acc[r][tid];
    }
  }

  // Store answers
  if (ii<inum && offset==0) {
    __global acctyp *ap1=engv+ii;
    if (eflag>0) {
      *ap1+=energy;
      ap1+=inum;
    }
    if (vflag>0) {
      for (int i=0; i<6; i++) {
        *ap1+=virial[i];
        ap1+=inum;
      }
    }
    acctyp4 old=ans[ii];
    old.x+=f.x;
    old.y+=f.y;
    old.z+=f.z;
    ans[ii]=old;
  } // if ii
}

#endif

