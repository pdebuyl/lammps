// **************************************************************************
//                                 gayberne.cu
//                             -------------------
//                               W. Michael Brown
//
//  Device code for Gay-Berne potential acceleration
//
// __________________________________________________________________________
//    This file is part of the LAMMPS Accelerator Library (LAMMPS_AL)
// __________________________________________________________________________
//
//    begin                :
//    email                : brownw@ornl.gov
// ***************************************************************************/

#ifndef GAYBERNE_CU
#define GAYBERNE_CU

#ifdef NV_KERNEL
#include "ellipsoid_extra.h"
#endif

#define SBBITS 30
#define NEIGHMASK 0x3FFFFFFF
__inline int sbmask(int j) { return j >> SBBITS & 3; }

__inline void compute_eta_torque(numtyp m[9],numtyp m2[9], const numtyp4 shape, 
                                 numtyp ans[9])
{
  numtyp den = m[3]*m[2]*m[7]-m[0]*m[5]*m[7]-
    m[2]*m[6]*m[4]+m[1]*m[6]*m[5]-
    m[3]*m[1]*m[8]+m[0]*m[4]*m[8];
  den = (numtyp)1.0/den;
  
  ans[0] = shape.x*(m[5]*m[1]*m2[2]+(numtyp)2.0*m[4]*m[8]*m2[0]-
		    m[4]*m2[2]*m[2]-(numtyp)2.0*m[5]*m2[0]*m[7]+
		    m2[1]*m[2]*m[7]-m2[1]*m[1]*m[8]-
		    m[3]*m[8]*m2[1]+m[6]*m[5]*m2[1]+
		    m[3]*m2[2]*m[7]-m2[2]*m[6]*m[4])*den;
  
  ans[1] = shape.x*(m[2]*m2[0]*m[7]-m[8]*m2[0]*m[1]+
		    (numtyp)2.0*m[0]*m[8]*m2[1]-m[0]*m2[2]*m[5]-
		    (numtyp)2.0*m[6]*m[2]*m2[1]+m2[2]*m[3]*m[2]-
		    m[8]*m[3]*m2[0]+m[6]*m2[0]*m[5]+
		    m[6]*m2[2]*m[1]-m2[2]*m[0]*m[7])*den;
  
  ans[2] = shape.x*(m[1]*m[5]*m2[0]-m[2]*m2[0]*m[4]-
		    m[0]*m[5]*m2[1]+m[3]*m[2]*m2[1]-
		    m2[1]*m[0]*m[7]-m[6]*m[4]*m2[0]+
		    (numtyp)2.0*m[4]*m[0]*m2[2]-(numtyp)2.0*m[3]*m2[2]*m[1]+
		    m[3]*m[7]*m2[0]+m[6]*m2[1]*m[1])*den;
  
  ans[3] = shape.y*(-m[4]*m2[5]*m[2]+(numtyp)2.0*m[4]*m[8]*m2[3]+
		    m[5]*m[1]*m2[5]-(numtyp)2.0*m[5]*m2[3]*m[7]+
		    m2[4]*m[2]*m[7]-m2[4]*m[1]*m[8]-
		    m[3]*m[8]*m2[4]+m[6]*m[5]*m2[4]-
		    m2[5]*m[6]*m[4]+m[3]*m2[5]*m[7])*den;
  
  ans[4] = shape.y*(m[2]*m2[3]*m[7]-m[1]*m[8]*m2[3]+
		    (numtyp)2.0*m[8]*m[0]*m2[4]-m2[5]*m[0]*m[5]-
		    (numtyp)2.0*m[6]*m2[4]*m[2]-m[3]*m[8]*m2[3]+
		    m[6]*m[5]*m2[3]+m[3]*m2[5]*m[2]-
		    m[0]*m2[5]*m[7]+m2[5]*m[1]*m[6])*den;
  
  ans[5] = shape.y*(m[1]*m[5]*m2[3]-m[2]*m2[3]*m[4]-
		    m[0]*m[5]*m2[4]+m[3]*m[2]*m2[4]+
		    (numtyp)2.0*m[4]*m[0]*m2[5]-m[0]*m2[4]*m[7]+
		    m[1]*m[6]*m2[4]-m2[3]*m[6]*m[4]-
		    (numtyp)2.0*m[3]*m[1]*m2[5]+m[3]*m2[3]*m[7])*den;
  
  ans[6] = shape.z*(-m[4]*m[2]*m2[8]+m[1]*m[5]*m2[8]+
		    (numtyp)2.0*m[4]*m2[6]*m[8]-m[1]*m2[7]*m[8]+
		    m[2]*m[7]*m2[7]-(numtyp)2.0*m2[6]*m[7]*m[5]-
		    m[3]*m2[7]*m[8]+m[5]*m[6]*m2[7]-
		    m[4]*m[6]*m2[8]+m[7]*m[3]*m2[8])*den;
  
  ans[7] = shape.z*-(m[1]*m[8]*m2[6]-m[2]*m2[6]*m[7]-
		     (numtyp)2.0*m2[7]*m[0]*m[8]+m[5]*m2[8]*m[0]+
		     (numtyp)2.0*m2[7]*m[2]*m[6]+m[3]*m2[6]*m[8]-
		     m[3]*m[2]*m2[8]-m[5]*m[6]*m2[6]+
		     m[0]*m2[8]*m[7]-m2[8]*m[1]*m[6])*den;
  
  ans[8] = shape.z*(m[1]*m[5]*m2[6]-m[2]*m2[6]*m[4]-
		    m[0]*m[5]*m2[7]+m[3]*m[2]*m2[7]-
		    m[4]*m[6]*m2[6]-m[7]*m2[7]*m[0]+
		    (numtyp)2.0*m[4]*m2[8]*m[0]+m[7]*m[3]*m2[6]+
		    m[6]*m[1]*m2[7]-(numtyp)2.0*m2[8]*m[3]*m[1])*den;
}

__kernel void kernel_ellipsoid(__global numtyp4* x_,__global numtyp4 *q,
                               __global numtyp4* shape, __global numtyp4* well, 
                               __global numtyp *gum, __global numtyp2* sig_eps, 
                               const int ntypes, __global numtyp *lshape, 
                               __global int *dev_nbor, const int stride, 
                               __global acctyp4 *ans, const int astride, 
                               __global acctyp *engv, __global int *err_flag, 
                               const int eflag, const int vflag, const int inum,
                               const int nall, const int t_per_atom) {
  int tid=THREAD_ID_X;
  int ii=mul24((int)BLOCK_ID_X,(int)(BLOCK_SIZE_X)/t_per_atom);
  ii+=tid/t_per_atom;
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
  acctyp4 tor;
  tor.x=(acctyp)0;
  tor.y=(acctyp)0;
  tor.z=(acctyp)0;
  acctyp virial[6];
  for (int i=0; i<6; i++)
    virial[i]=(acctyp)0;

  if (ii<inum) {
    __global int *nbor=dev_nbor+ii;
    int i=*nbor;
    nbor+=stride;
    int numj=*nbor;
    nbor+=stride;
    __global int *nbor_end=nbor+mul24(stride,numj);
    nbor+=mul24(offset,stride);
    int n_stride=mul24(t_per_atom,stride);
  
    numtyp4 ix=x_[i];
    int itype=ix.w;
    numtyp a1[9], b1[9], g1[9];
    numtyp4 ishape=shape[itype];
    {
      numtyp t[9];
      gpu_quat_to_mat_trans(q,i,a1);
      gpu_diag_times3(ishape,a1,t);
      gpu_transpose_times3(a1,t,g1);
      gpu_diag_times3(well[itype],a1,t);
      gpu_transpose_times3(a1,t,b1);
    }

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

      numtyp a2[9];
      gpu_quat_to_mat_trans(q,j,a2);
  
      numtyp u_r, dUr[3], tUr[3], eta, teta[3];
      { // Compute U_r, dUr, eta, and teta
        // Compute g12
        numtyp g12[9];
        {
          numtyp g2[9];
          {
              gpu_diag_times3(shape[jtype],a2,g12);
              gpu_transpose_times3(a2,g12,g2);
              gpu_plus3(g1,g2,g12);
          }

          { // Compute U_r and dUr
    
            // Compute kappa
            numtyp kappa[3];
            gpu_mldivide3(g12,r12,kappa,err_flag);

            // -- replace r12 with r12 hat
            r12[0]*=ir;
            r12[1]*=ir;
            r12[2]*=ir;

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
              sigma12 = gpu_dot3(r12,kappa);
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
              numtyp temp2 = gpu_dot3(kappa,r12);
              uslj_rsq = uslj_rsq*ir*ir;

              dUr[0] = temp1*r12[0]+uslj_rsq*(kappa[0]-temp2*r12[0]);
              dUr[1] = temp1*r12[1]+uslj_rsq*(kappa[1]-temp2*r12[1]);
              dUr[2] = temp1*r12[2]+uslj_rsq*(kappa[2]-temp2*r12[2]);
            }

            // torque for particle 1
            {
              numtyp tempv[3], tempv2[3];
              tempv[0] = -uslj_rsq*kappa[0];
              tempv[1] = -uslj_rsq*kappa[1];
              tempv[2] = -uslj_rsq*kappa[2];
              gpu_row_times3(kappa,g1,tempv2);
              gpu_cross3(tempv,tempv2,tUr);
            }
          }
        }
     
        // Compute eta
        {
          eta = (numtyp)2.0*lshape[itype]*lshape[jtype];
          numtyp det_g12 = gpu_det3(g12);
          eta = pow(eta/det_g12,gum[1]);
        }
    
        // Compute teta
        numtyp temp[9], tempv[3], tempv2[3];
        compute_eta_torque(g12,a1,ishape,temp);
        numtyp temp1 = -eta*gum[1];

        tempv[0] = temp1*temp[0];
        tempv[1] = temp1*temp[1];
        tempv[2] = temp1*temp[2];
        gpu_cross3(a1,tempv,tempv2);
        teta[0] = tempv2[0];
        teta[1] = tempv2[1];
        teta[2] = tempv2[2];
  
        tempv[0] = temp1*temp[3];
        tempv[1] = temp1*temp[4];
        tempv[2] = temp1*temp[5];
        gpu_cross3(a1+3,tempv,tempv2);
        teta[0] += tempv2[0];
        teta[1] += tempv2[1];
        teta[2] += tempv2[2];

        tempv[0] = temp1*temp[6];
        tempv[1] = temp1*temp[7];
        tempv[2] = temp1*temp[8];
        gpu_cross3(a1+6,tempv,tempv2);
        teta[0] += tempv2[0];
        teta[1] += tempv2[1];
        teta[2] += tempv2[2];
      }
  
      numtyp chi, dchi[3], tchi[3];
      { // Compute chi and dchi

        // Compute b12
        numtyp b2[9], b12[9];
        {
          gpu_diag_times3(well[jtype],a2,b12);
          gpu_transpose_times3(a2,b12,b2);
          gpu_plus3(b1,b2,b12);
        }

        // compute chi_12
        r12[0]*=r;
        r12[1]*=r;
        r12[2]*=r;
        numtyp iota[3];
        gpu_mldivide3(b12,r12,iota,err_flag);
        // -- iota is now iota/r
        iota[0]*=ir;
        iota[1]*=ir;
        iota[2]*=ir;
        r12[0]*=ir;
        r12[1]*=ir;
        r12[2]*=ir;
        chi = gpu_dot3(r12,iota);
        chi = pow(chi*(numtyp)2.0,gum[2]);

        // -- iota is now ok
        iota[0]*=r;
        iota[1]*=r;
        iota[2]*=r;

        numtyp temp1 = gpu_dot3(iota,r12);
        numtyp temp2 = (numtyp)-4.0*ir*ir*gum[2]*pow(chi,(gum[2]-(numtyp)1.0)/
                                                          gum[2]);
        dchi[0] = temp2*(iota[0]-temp1*r12[0]);
        dchi[1] = temp2*(iota[1]-temp1*r12[1]);
        dchi[2] = temp2*(iota[2]-temp1*r12[2]);

        // compute t_chi
        numtyp tempv[3];
        gpu_row_times3(iota,b1,tempv);
        gpu_cross3(tempv,iota,tchi);
        temp1 = (numtyp)-4.0*ir*ir;
        tchi[0] *= temp1;
        tchi[1] *= temp1;
        tchi[2] *= temp1;
      }

      numtyp temp2 = factor_lj*eta*chi;
      if (eflag>0)
        energy+=u_r*temp2;
      numtyp temp1 = -eta*u_r*factor_lj;
      if (vflag>0) {
        r12[0]*=-r;
        r12[1]*=-r;
        r12[2]*=-r;
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

      // Torque on 1
      temp1 = -u_r*eta*factor_lj;
      temp2 = -u_r*chi*factor_lj;
      numtyp temp3 = -chi*eta*factor_lj;
      tor.x+=temp1*tchi[0]+temp2*teta[0]+temp3*tUr[0];
      tor.y+=temp1*tchi[1]+temp2*teta[1]+temp3*tUr[1];
      tor.z+=temp1*tchi[2]+temp2*teta[2]+temp3*tUr[2];
 
    } // for nbor
  } // if ii
  
  // Reduce answers
  if (t_per_atom>1) {
    __local acctyp red_acc[7][BLOCK_PAIR];
    
    red_acc[0][tid]=f.x;
    red_acc[1][tid]=f.y;
    red_acc[2][tid]=f.z;
    red_acc[3][tid]=tor.x;
    red_acc[4][tid]=tor.y;
    red_acc[5][tid]=tor.z;

    for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
      if (offset < s) {
        for (int r=0; r<6; r++)
          red_acc[r][tid] += red_acc[r][tid+s];
      }
    }
    
    f.x=red_acc[0][tid];
    f.y=red_acc[1][tid];
    f.z=red_acc[2][tid];
    tor.x=red_acc[3][tid];
    tor.y=red_acc[4][tid];
    tor.z=red_acc[5][tid];

    if (eflag>0 || vflag>0) {
      for (int r=0; r<6; r++)
        red_acc[r][tid]=virial[r];
      red_acc[6][tid]=energy;

      for (unsigned int s=t_per_atom/2; s>0; s>>=1) {
        if (offset < s) {
          for (int r=0; r<7; r++)
            red_acc[r][tid] += red_acc[r][tid+s];
        }
      }
    
      for (int r=0; r<6; r++)
        virial[r]=red_acc[r][tid];
      energy=red_acc[6][tid];
    }
  }

  // Store answers
  if (ii<inum && offset==0) {
    __global acctyp *ap1=engv+ii;
    if (eflag>0) {
      *ap1=energy;
      ap1+=astride;
    }
    if (vflag>0) {
      for (int i=0; i<6; i++) {
        *ap1=virial[i];
        ap1+=astride;
      }
    }
    ans[ii]=f;
    ans[ii+astride]=tor;
  } // if ii
}

#endif

