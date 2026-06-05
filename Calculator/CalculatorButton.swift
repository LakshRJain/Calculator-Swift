//
//  CalculatorButton.swift
//  Calculator
//
//  Created by Laksh on 04/06/26.
//

import UIKit

final class CalculatorButton: UIButton {

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = bounds.height / 2
    }
    
}
