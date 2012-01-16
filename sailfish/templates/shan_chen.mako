<%
	from sailfish import sym
%>

<%def name="sc_calculate_accel()">
##
## Declare and evaluate the Shan-Chen accelerations.
##
	%for x in set(sum(force_couplings.keys(), ())):
		float sca${x}[${dim}];
	%endfor

	if (!isWallNode(type)) {
		%for dists, coupling_const in force_couplings.iteritems():

			// Interaction between two components.
			%if dists[0] != dists[1]:
				%if dim == 2:
					shan_chen_force(gi, gg${dists[0]}m0, gg${dists[1]}m0,
						${coupling_const}, sca${dists[0]}, sca${dists[1]}, gx, gy);
				%else:
					shan_chen_force(gi, gg${dists[0]}m0, gg${dists[1]}m0,
						${coupling_const}, sca${dists[0]}, sca${dists[1]}, gx, gy, gz);
				%endif
			// Self-interaction of a single component.
			%else:
				%if dim == 2:
					shan_chen_accel_self(gi, gg${dists[0]}m0, ${dists[0]}, ${coupling_const}, sca${dists[0]}, gx, gy);
				%else:
					shan_chen_accel_self(gi, gg${dists[0]}m0, ${dists[0]}, ${coupling_const}, sca${dists[0]}, gx, gy, gz);
				%endif
			%endif
		%endfor
	}
</%def>

<%def name="sc_macro_fields()">
	// Calculate the density and velocity for the Shan-Chen coupled fields.
	// Density and velocity become weighted averages of the values for invidual components.
	float total_dens;

	%for i, x in enumerate(set(sum(force_couplings.keys(), ()))):
		get0thMoment(&d${x}, type, orientation, &g${x}m0);
		compute_1st_moment(&d${x}, v, ${i}, 1.0f/tau${x});
	%endfor

	total_dens = 0.0f;
	%for x in set(sum(force_couplings.keys(), ())):
		total_dens += g${x}m0 / tau${x};
	%endfor

	// Transfer momentum and force into velocity and acceleration.
	%for i in range(0, dim):
		%for x in set(sum(force_couplings.keys(), ())):
			sca${x}[${i}] /= g${x}m0;
		%endfor
		v[${i}] /= total_dens;
	%endfor
</%def>

<%def name="get_field_loc(xoff, yoff, zoff)">
	nx = x + ${xoff};
	ny = y + ${yoff};
	%if dim == 3:
		nz = z + ${zoff};
	%endif

	%if xoff != 0:
		%if periodicity[0]:
			// Periodic boundary conditions.
			%if xoff > 0:
				if (nx > ${lat_nx-1}) {	nx = 0;				}
			%else:
				if (nx < 0) {			nx = ${lat_nx-1};	}
			%endif
		%else:
			// Mirror boundary conditions.
			%if xoff > 0:
				if (nx > ${lat_nx-1}) {	nx = ${lat_nx-1};	}
			%else:
				if (nx < 0) {			nx = 0;				}
			%endif
		%endif
	%endif

	%if yoff != 0:
		%if periodicity[1]:
			%if yoff > 0:
				if (ny > ${lat_ny-1}) {	ny = 0;				}
			%else:
				if (ny < 0) {			ny = ${lat_ny-1};	}
			%endif
		%else:
			%if yoff > 0:
				if (ny > ${lat_ny-1}) {	ny = ${lat_ny-1};	}
			%else:
				if (ny < 0) {			ny = 0;				}
			%endif
		%endif
	%endif

	%if zoff != 0:
		%if periodicity[2]:
			%if zoff > 0:
				if (nz > ${lat_nz-1}) {	nz = 0;				}
			%else:
				if (nz < 0) {			nz = ${lat_nz-1};	}
			%endif
		%else:
			%if zoff > 0:
				if (nz > ${lat_nz-1}) {	nz = ${lat_nz-1};	}
			%else:
				if (nz < 0) {			nz = 0;				}
			%endif
		%endif
	%endif

	%if dim == 2:
		gi = getGlobalIdx(nx, ny);
	%else:
		gi = getGlobalIdx(nx, ny, nz);
	%endif
</%def>

// Calculates the Shan-Chan pseudopotential.
${device_func} inline float sc_ppot(${global_ptr} float *field, int gi)
{
	float lfield = field[gi];
	return ${sym.SHAN_CHEN_POTENTIALS[sc_potential]('lfield')};
}

// Calculates the Shan-Chen force between a single fluid components (self-interaction).
// The form of the interaction is the same as that of a force between two components (see below).
${device_func} inline void shan_chen_accel_self(int i, ${global_ptr} float *f1, float cc, float *a1, int x, int y
%if dim == 3:
	, int z
%endif
)
{
	float t1;

	%for i in range(0, dim):
		a1[${i}] = 0.0f;
	%endfor

	int nx, ny;
	%if dim == 3:
		int nz;
	%endif

	int gi;		// global index

	%for i, ve in enumerate(grid.basis):
		%if ve.dot(ve) != 0.0:
			// ${ve}
			%if dim == 3:
				${get_field_loc(ve[0], ve[1], ve[2])};
			%else:
				${get_field_loc(ve[0], ve[1], 0)};
			%endif

			t1 = sc_ppot(f1, gi);

			%if ve[0] != 0:
				a1[0] += t1 * ${ve[0] * grid.weights[i]};
			%endif
			%if ve[1] != 0:
				a1[1] += t1 * ${ve[1] * grid.weights[i]};
			%endif
			%if dim == 3 and ve[2] != 0:
				a1[2] += t1 * ${ve[2] * grid.weights[i]};
			%endif
		%endif
	%endfor

	// Local node -- no offset.
	nx = x;
	ny = y;
	%if dim == 3:
		nz = z;
	%endif

	t1 = sc_ppot(f1, i);

	%for i in range(0, dim):
		a1[${i}] *= t1 * cc;
	%endfor
}

// Calculates the Shan-Chen force between two fluid components.
//
//  F = -G * \phi_A(x) \sum_i w_i e_i \phi_B(x + e_i)
//
// i: global node index
// f1, f2: fields
// cc: coupling constant
// a1, a2: Shan-Chen accelerations (output variables)
// x, y, [z]: position of the node
${device_func} inline void shan_chen_force(int i, ${global_ptr} float *f1, ${global_ptr} float *f2,
float cc, float *a1, float *a2, int x, int y
%if dim == 3:
	, int z
%endif
)
{
	float t1, t2;

	%for i in range(0, dim):
		a1[${i}] = 0.0f;
		a2[${i}] = 0.0f;
	%endfor

	int nx, ny;
	%if dim == 3:
		int nz;
	%endif

	int gi;		// global index

	%for i, ve in enumerate(grid.basis):
		%if ve.dot(ve) != 0.0:
			// ${ve}
			%if dim == 3:
				${get_field_loc(ve[0], ve[1], ve[2])};
			%else:
				${get_field_loc(ve[0], ve[1], 0)};
			%endif

			t1 = sc_ppot(f1, gi);
			t2 = sc_ppot(f2, gi);

			%if ve[0] != 0:
				a1[0] += t2 * ${ve[0] * grid.weights[i]};
				a2[0] += t1 * ${ve[0] * grid.weights[i]};
			%endif
			%if ve[1] != 0:
				a1[1] += t2 * ${ve[1] * grid.weights[i]};
				a2[1] += t1 * ${ve[1] * grid.weights[i]};
			%endif
			%if dim == 3 and ve[2] != 0:
				a1[2] += t2 * ${ve[2] * grid.weights[i]};
				a2[2] += t1 * ${ve[2] * grid.weights[i]};
			%endif
		%endif
	%endfor

	// Local node -- no offset.
	nx = x;
	ny = y;
	%if dim == 3:
		nz = z;
	%endif

	t1 = sc_ppot(f1, i);
	t2 = sc_ppot(f2, i);

	%for i in range(0, dim):
		a1[${i}] *= - t1 * cc;
		a2[${i}] *= - t2 * cc;
	%endfor
}
