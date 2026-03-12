<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use Illuminate\Http\Request;

class ProductController extends Controller
{
    private function hasAccess(Request $request, int $companyId): bool
    {
        return $request->user()->companies()
            ->where('companies.id', $companyId)
            ->exists();
    }

    /** GET /api/products?company_id= */
    public function index(Request $request)
    {
        $request->validate(['company_id' => 'required|integer']);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $products = Product::where('company_id', $request->company_id)
            ->where('is_active', true)
            ->orderBy('name')
            ->get();

        return response()->json(['success' => true, 'products' => $products]);
    }

    /** POST /api/products */
    public function store(Request $request)
    {
        $data = $request->validate([
            'company_id'   => 'required|integer',
            'sku'          => 'required|string|max:100',
            'name'         => 'required|string|max:255',
            'category_id'  => 'nullable|integer',
            'uom_id'       => 'nullable|integer',
            'is_tracked'   => 'nullable|boolean',
            'last_cost'    => 'nullable|numeric',
            'sale_price'   => 'nullable|numeric',
            'opening_qty'  => 'nullable|numeric',
            'is_active'    => 'nullable|boolean',
        ]);

        if (!$this->hasAccess($request, $data['company_id'])) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $product = Product::create($data);

        return response()->json([
            'success' => true,
            'message' => 'Product created successfully',
            'product' => $product,
        ], 201);
    }

    /** PUT /api/products/{id} */
    public function update(Request $request, int $id)
    {
        $product = Product::findOrFail($id);

        if (!$this->hasAccess($request, $product->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $data = $request->validate([
            'sku'          => 'sometimes|required|string|max:100',
            'name'         => 'sometimes|required|string|max:255',
            'category_id'  => 'nullable|integer',
            'uom_id'       => 'nullable|integer',
            'is_tracked'   => 'nullable|boolean',
            'last_cost'    => 'nullable|numeric',
            'sale_price'   => 'nullable|numeric',
            'opening_qty'  => 'nullable|numeric',
            'is_active'    => 'nullable|boolean',
        ]);

        $product->update($data);

        return response()->json([
            'success' => true,
            'message' => 'Product updated successfully',
            'product' => $product,
        ]);
    }

    /** DELETE /api/products/{id} */
    public function destroy(Request $request, int $id)
    {
        $product = Product::findOrFail($id);

        if (!$this->hasAccess($request, $product->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $product->update(['is_active' => false]);

        return response()->json(['success' => true, 'message' => 'Product deactivated successfully']);
    }
}
